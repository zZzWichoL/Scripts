// ESP32: Versión Mejorada para Flutter
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <ESPmDNS.h>

// Datos del AP por defecto
const char* ap_ssid = "Gasox";
const char* ap_password = "12345678";
const char* device_name = "gasox-monitor";

// Variables de WiFi
String ssid = "";
String password = "";
bool wifiConnected = false;

// Objeto para guardar preferencias
Preferences preferences;

// Servidor web
WebServer server(80);

// Pines sensores y actuadores
const int mq4Pin = 34;
const int mq7Pin = 35;
const int ledPin = 13;
const int buzzerPin = 26;

// Umbrales de gas
float mq4Threshold = 50.0;
float mq7Threshold = 50.0;

// Lecturas de sensores
float mq4Value = 0.0;
float mq7Value = 0.0;
bool alarmActive = false;

// Calibración de sensores
float mq4Offset = 0.0;
float mq7Offset = 0.0;

// Variables para alarma
unsigned long lastBlink = 0;
bool alarmState = false;
const unsigned long blinkInterval = 300;

// Historial de lecturas (últimas 10)
struct Reading {
  unsigned long timestamp;
  float mq4;
  float mq7;
  bool alarm;
};

Reading history[10];
int historyIndex = 0;

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("=== INICIANDO SISTEMA GASOX ===");

  pinMode(ledPin, OUTPUT);
  pinMode(buzzerPin, OUTPUT);
  
  // Test inicial de componentes
  testComponents();

  // Cargar configuración
  loadConfiguration();

  // Intentar conectar si hay credenciales
  if (ssid.length() > 0) connectToWiFi();
  if (!wifiConnected) createAccessPoint();

  // Configurar mDNS
  if (MDNS.begin(device_name)) {
    Serial.println("✓ mDNS iniciado: " + String(device_name) + ".local");
    MDNS.addService("http", "tcp", 80);
  }

  setupRoutes();
  server.begin();
  Serial.println("✓ Servidor HTTP iniciado en puerto 80");

  printNetworkInfo();
  Serial.println("=== SISTEMA LISTO ===");
}

void testComponents() {
  Serial.println("Probando componentes...");
  
  // Test LED
  digitalWrite(ledPin, HIGH);
  delay(200);
  digitalWrite(ledPin, LOW);
  
  // Test Buzzer
  digitalWrite(buzzerPin, HIGH);
  delay(100);
  digitalWrite(buzzerPin, LOW);
  
  Serial.println("✓ Componentes OK");
}

void loadConfiguration() {
  preferences.begin("gasox", true);
  ssid = preferences.getString("ssid", "");
  password = preferences.getString("password", "");
  mq4Threshold = preferences.getFloat("mq4_thresh", 50.0);
  mq7Threshold = preferences.getFloat("mq7_thresh", 50.0);
  mq4Offset = preferences.getFloat("mq4_offset", 0.0);
  mq7Offset = preferences.getFloat("mq7_offset", 0.0);
  preferences.end();

  Serial.println("Configuración cargada:");
  Serial.println("  SSID: " + ssid);
  Serial.println("  MQ4 Threshold: " + String(mq4Threshold));
  Serial.println("  MQ7 Threshold: " + String(mq7Threshold));
}

void saveConfiguration() {
  preferences.begin("gasox", false);
  preferences.putString("ssid", ssid);
  preferences.putString("password", password);
  preferences.putFloat("mq4_thresh", mq4Threshold);
  preferences.putFloat("mq7_thresh", mq7Threshold);
  preferences.putFloat("mq4_offset", mq4Offset);
  preferences.putFloat("mq7_offset", mq7Offset);
  preferences.end();
}

void connectToWiFi() {
  Serial.println("Intentando conectar a WiFi...");
  WiFi.mode(WIFI_STA); // Cambiar a solo modo Station
  WiFi.begin(ssid.c_str(), password.c_str());
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 60) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✓ Conectado a WiFi");
    Serial.println("  IP: " + WiFi.localIP().toString());
    wifiConnected = true;
  } else {
    Serial.println("\n✗ Fallo conexión WiFi");
    wifiConnected = false;
    // Si falla la conexión, crear AP
    createAccessPoint();
  }
}

void createAccessPoint() {
  Serial.println("Creando punto de acceso...");
  WiFi.mode(WIFI_AP);
  delay(1000);

  if (WiFi.softAP(ap_ssid, ap_password)) {
    Serial.println("✓ Punto de acceso creado");
    Serial.println("  IP del AP: " + WiFi.softAPIP().toString());
  } else {
    Serial.println("✗ Error creando punto de acceso");
  }
}

void printNetworkInfo() {
  Serial.println("\n=== INFORMACIÓN DE RED ===");
  Serial.println("Modo WiFi: " + String(WiFi.getMode() == WIFI_AP ? "AP" :
                WiFi.getMode() == WIFI_STA ? "STA" : "AP+STA"));

  if (WiFi.getMode() & WIFI_AP) {
    Serial.println("AP SSID: " + WiFi.softAPSSID());
    Serial.println("AP IP: " + WiFi.softAPIP().toString());
  }

  if (WiFi.getMode() & WIFI_STA && WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi SSID: " + WiFi.SSID());
    Serial.println("WiFi IP: " + WiFi.localIP().toString());
  }
  Serial.println("===========================\n");
}

void addToHistory(float mq4, float mq7, bool alarm) {
  history[historyIndex] = {millis(), mq4, mq7, alarm};
  historyIndex = (historyIndex + 1) % 10;
}

float readMQ4() {
  int rawValue = analogRead(mq4Pin);
  float voltage = (rawValue / 4095.0) * 3.3;
  float ppm = (voltage - mq4Offset) * 100; // Conversión simplificada
  return max(0.0f, ppm);
}

float readMQ7() {
  int rawValue = analogRead(mq7Pin);
  float voltage = (rawValue / 4095.0) * 3.3;
  float ppm = (voltage - mq7Offset) * 100; // Conversión simplificada
  return max(0.0f, ppm);
}

void setupRoutes() {
  // Habilitar CORS para todas las rutas
  server.enableCORS(true);

  // Página principal
  server.on("/", HTTP_GET, []() {
    String html = R"(
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1'>
    <title>Gasox Monitor</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .connected { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .disconnected { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .reading { display: inline-block; margin: 10px; padding: 15px; background: #e9ecef; border-radius: 5px; min-width: 150px; text-align: center; }
        .alarm { background: #f8d7da !important; color: #721c24; }
        a { color: #007bff; text-decoration: none; margin: 0 10px; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>🔥 Gasox - Monitor de Gases</h1>
        
        <div class='status )" + String(wifiConnected ? "connected" : "disconnected") + R"('>
            <strong>Estado WiFi:</strong> )" + String(wifiConnected ? "Conectado a " + WiFi.SSID() : "Desconectado") + R"(
        </div>
        
        <div class='status connected'>
            <strong>Modo AP:</strong> )" + String(ap_ssid) + R"( ()" + WiFi.softAPIP().toString() + R"())
        </div>
        
        <h3>Lecturas Actuales</h3>
        <div class='reading )" + String(mq4Value > mq4Threshold ? "alarm" : "") + R"('>
            <strong>MQ4 (Metano)</strong><br>
            )" + String(mq4Value, 1) + R"( ppm<br>
            <small>Umbral: )" + String(mq4Threshold, 1) + R"( ppm</small>
        </div>
        
        <div class='reading )" + String(mq7Value > mq7Threshold ? "alarm" : "") + R"('>
            <strong>MQ7 (CO)</strong><br>
            )" + String(mq7Value, 1) + R"( ppm<br>
            <small>Umbral: )" + String(mq7Threshold, 1) + R"( ppm</small>
        </div>
        
        <h3>Enlaces API</h3>
        <div>
            <a href='/api/readings'>Lecturas JSON</a>
            <a href='/api/status'>Estado JSON</a>
            <a href='/api/history'>Historial</a>
            <a href='/api/device'>Info Dispositivo</a>
        </div>
        
        <script>
            setInterval(() => location.reload(), 5000);
        </script>
    </div>
</body>
</html>
    )";
    server.send(200, "text/html", html);
  });

  // API: Lecturas de sensores
  server.on("/api/readings", HTTP_GET, []() {
    mq4Value = readMQ4();
    mq7Value = readMQ7();
    
    DynamicJsonDocument doc(512);
    doc["timestamp"] = millis();
    doc["mq4"]["value"] = round(mq4Value * 10) / 10.0;
    doc["mq4"]["threshold"] = mq4Threshold;
    doc["mq4"]["alarm"] = mq4Value > mq4Threshold;
    doc["mq7"]["value"] = round(mq7Value * 10) / 10.0;
    doc["mq7"]["threshold"] = mq7Threshold;
    doc["mq7"]["alarm"] = mq7Value > mq7Threshold;
    doc["alarm_active"] = alarmActive;
    doc["uptime"] = millis();
    
    String response;
    serializeJson(doc, response);
    server.send(200, "application/json", response);
  });

  // API: Estado del sistema
  server.on("/api/status", HTTP_GET, []() {
    DynamicJsonDocument doc(1024);
    doc["device"]["name"] = device_name;
    doc["device"]["version"] = "2.0";
    doc["device"]["uptime"] = millis();
    doc["device"]["free_heap"] = ESP.getFreeHeap();
    doc["device"]["total_heap"] = ESP.getHeapSize();
    doc["device"]["cpu_freq"] = ESP.getCpuFreqMHz();
    
    doc["network"]["ap"]["ssid"] = ap_ssid;
    doc["network"]["ap"]["ip"] = WiFi.softAPIP().toString();
    doc["network"]["ap"]["clients"] = WiFi.softAPgetStationNum();
    
    doc["network"]["wifi"]["connected"] = wifiConnected;
    if (wifiConnected) {
        doc["network"]["wifi"]["ssid"] = WiFi.SSID();
        doc["network"]["wifi"]["ip"] = WiFi.localIP().toString();
        doc["network"]["wifi"]["rssi"] = WiFi.RSSI();
    }
    
    String response;
    serializeJson(doc, response);
    server.send(200, "application/json", response);
  });

  // API: Historial de lecturas
  server.on("/api/history", HTTP_GET, []() {
    DynamicJsonDocument doc(2048);
    JsonArray readings = doc.createNestedArray("readings");
    
    for (int i = 0; i < 10; i++) {
        int idx = (historyIndex + i) % 10;
        if (history[idx].timestamp > 0) {
            JsonObject reading = readings.createNestedObject();
            reading["timestamp"] = history[idx].timestamp;
            reading["mq4"] = history[idx].mq4;
            reading["mq7"] = history[idx].mq7;
            reading["alarm"] = history[idx].alarm;
        }
    }
    
    String response;
    serializeJson(doc, response);
    server.send(200, "application/json", response);
  });

  // API: Información del dispositivo
  server.on("/api/device", HTTP_GET, []() {
    DynamicJsonDocument doc(512);
    doc["name"] = device_name;
    doc["version"] = "2.0";
    doc["chip_model"] = ESP.getChipModel();
    doc["chip_revision"] = ESP.getChipRevision();
    doc["flash_size"] = ESP.getFlashChipSize();
    doc["sketch_size"] = ESP.getSketchSize();
    doc["free_sketch_space"] = ESP.getFreeSketchSpace();
    
    String response;
    serializeJson(doc, response);
    server.send(200, "application/json", response);
  });

  // API: Configurar WiFi
  server.on("/api/wifi/configure", HTTP_POST, []() {
    if (!server.hasArg("plain")) {
        server.send(400, "application/json", "{\"error\":\"No JSON data received\"}");
        return;
    }
    
    DynamicJsonDocument doc(512);
    deserializeJson(doc, server.arg("plain"));
    
    if (!doc.containsKey("ssid") || !doc.containsKey("password")) {
        server.send(400, "application/json", "{\"error\":\"Missing ssid or password\"}");
        return;
    }
    
    ssid = doc["ssid"].as<String>();
    password = doc["password"].as<String>();
    
    saveConfiguration();
    
    server.send(200, "application/json", "{\"message\":\"WiFi configured, restarting...\"}");
    delay(1000);
    ESP.restart();
  });

  // API: Olvinar WiFi
  server.on("/api/wifi/forget", HTTP_POST, []() {
    preferences.begin("gasox", false);
    preferences.remove("ssid");
    preferences.remove("password");
    preferences.end();
    
    server.send(200, "application/json", "{\"message\":\"WiFi forgotten, restarting...\"}");
    delay(1000);
    ESP.restart();
  });

  // API: Configurar umbrales
  server.on("/api/thresholds", HTTP_GET, []() {
    DynamicJsonDocument doc(256);
    doc["mq4"] = mq4Threshold;
    doc["mq7"] = mq7Threshold;
    
    String response;
    serializeJson(doc, response);
    server.send(200, "application/json", response);
  });

  server.on("/api/thresholds", HTTP_POST, []() {
    if (!server.hasArg("plain")) {
        server.send(400, "application/json", "{\"error\":\"No JSON data received\"}");
        return;
    }
    
    DynamicJsonDocument doc(256);
    deserializeJson(doc, server.arg("plain"));
    
    if (doc.containsKey("mq4")) mq4Threshold = doc["mq4"];
    if (doc.containsKey("mq7")) mq7Threshold = doc["mq7"];
    
    saveConfiguration();
    
    server.send(200, "application/json", "{\"message\":\"Thresholds updated\"}");
  });

  // API: Calibrar sensores
  server.on("/api/calibrate", HTTP_POST, []() {
    // Tomar lecturas base para calibración
    float mq4Raw = 0, mq7Raw = 0;
    for (int i = 0; i < 10; i++) {
        mq4Raw += analogRead(mq4Pin);
        mq7Raw += analogRead(mq7Pin);
        delay(100);
    }
    
    mq4Offset = (mq4Raw / 10.0 / 4095.0) * 3.3;
    mq7Offset = (mq7Raw / 10.0 / 4095.0) * 3.3;
    
    saveConfiguration();
    
    DynamicJsonDocument doc(256);
    doc["message"] = "Calibration completed";
    doc["mq4_offset"] = mq4Offset;
    doc["mq7_offset"] = mq7Offset;
    
    String response;
    serializeJson(doc, response);
    server.send(200, "application/json", response);
  });

  // API: Control de alarma
  server.on("/api/alarm/silence", HTTP_POST, []() {
    digitalWrite(ledPin, LOW);
    digitalWrite(buzzerPin, LOW);
    alarmState = false;
    
    server.send(200, "application/json", "{\"message\":\"Alarm silenced\"}");
  });

  // API: Test de componentes
  server.on("/api/test", HTTP_POST, []() {
    testComponents();
    server.send(200, "application/json", "{\"message\":\"Component test completed\"}");
  });

  // Manejador 404
  server.onNotFound([]() {
    server.send(404, "application/json", "{\"error\":\"Endpoint not found\"}");
  });
}

void loop() {
  server.handleClient();

  // Verificar conexión WiFi cada 30s
  static unsigned long lastWiFiCheck = 0;
  if (millis() - lastWiFiCheck > 30000) {
    lastWiFiCheck = millis();
    if (ssid.length() > 0 && WiFi.status() != WL_CONNECTED && wifiConnected) {
      Serial.println("Reconectando WiFi...");
      wifiConnected = false;
      connectToWiFi();
    }
  }

  // Leer sensores cada segundo
  static unsigned long lastReading = 0;
  if (millis() - lastReading > 1000) {
    lastReading = millis();
    
    mq4Value = readMQ4();
    mq7Value = readMQ7();
    
    // Verificar alarma
    bool shouldAlarm = (mq4Value > mq4Threshold) || (mq7Value > mq7Threshold);
    
    if (shouldAlarm != alarmActive) {
      alarmActive = shouldAlarm;
      Serial.println("Estado alarma: " + String(alarmActive ? "ACTIVA" : "INACTIVA"));
    }
    
    // Agregar al historial cada 10 segundos
    static unsigned long lastHistory = 0;
    if (millis() - lastHistory > 10000) {
      lastHistory = millis();
      addToHistory(mq4Value, mq7Value, alarmActive);
    }
  }

  // Manejar alarma visual/sonora
  if (alarmActive) {
    unsigned long now = millis();
    if (now - lastBlink > blinkInterval) {
      lastBlink = now;
      alarmState = !alarmState;
      digitalWrite(ledPin, alarmState ? HIGH : LOW);
      digitalWrite(buzzerPin, alarmState ? HIGH : LOW);
    }
  } else {
    digitalWrite(ledPin, LOW);
    digitalWrite(buzzerPin, LOW);
    alarmState = false;
  }

  delay(10); // Pequeña pausa para estabilidad
}