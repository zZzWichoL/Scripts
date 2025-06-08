#include <WiFiManager.h>
#include <ESPmDNS.h>

WiFiServer server(8080);
const int LED_PIN = 13;
unsigned long lastPrintTime = 0;

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  WiFiManager wifiManager;
  // wifiManager.resetSettings(); // Descomenta para borrar redes guardadas
  wifiManager.autoConnect("GASOX"); // Nombre de la red temporal

  Serial.println("WiFi conectado!");
  Serial.print("Dirección IP: ");
  Serial.println(WiFi.localIP());

  // Iniciar mDNS
  if (MDNS.begin("esp32")) {
    Serial.println("mDNS responder iniciado: esp32.local");
  } else {
    Serial.println("Error al iniciar mDNS");
  }

  server.begin();
  server.setNoDelay(true);
}

void loop() {
  // Verificar estado WiFi cada 10 segundos
  if (millis() - lastPrintTime > 10000) {
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("WiFi conectado - IP: " + WiFi.localIP().toString());
      Serial.println("Servidor TCP activo - Puerto: 8080");
    } else {
      Serial.println("WiFi desconectado - Esperando configuración...");
    }
    lastPrintTime = millis();
  }

  WiFiClient client = server.available();

  if (client) {
    Serial.println("¡Cliente conectado!");
    unsigned long lastCommandTime = millis();

    while (client.connected()) {
      if (client.available()) {
        String command = client.readStringUntil('\n');
        command.trim();
        lastCommandTime = millis();

        if (command == "LED_ON") {
          digitalWrite(LED_PIN, HIGH);
          client.println("LED_ENCENDIDO");
        } else if (command == "LED_OFF") {
          digitalWrite(LED_PIN, LOW);
          client.println("LED_APAGADO");
        } else if (command == "STATUS") {
          int ledState = digitalRead(LED_PIN);
          client.println(ledState == HIGH ? "LED_ENCENDIDO" : "LED_APAGADO");
        } else if (command == "PING") {
          client.println("PONG");
        } else if (command == "FORGET_WIFI") {
          client.println("OLVIDANDO_WIFI");
          client.flush();
          delay(100);
          WiFi.disconnect(true, true);
          ESP.restart();
        } else {
          client.println("COMANDO_DESCONOCIDO");
        }
        client.flush();
      }

      // Si pasan más de 30 segundos sin comandos, cierra la conexión
      if (millis() - lastCommandTime > 30000) {
        Serial.println("Timeout de inactividad, cerrando cliente.");
        break;
      }
      delay(10);
    }
    client.stop();
    Serial.println("Cliente desconectado");
  }
}
