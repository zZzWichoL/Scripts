import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';

class NetworkConfigScreen extends StatefulWidget {
  const NetworkConfigScreen({super.key});

  @override
  State<NetworkConfigScreen> createState() => _NetworkConfigScreenState();
}

class _NetworkConfigScreenState extends State<NetworkConfigScreen> {
  String esp32ApIp = '';
  String esp32WifiIp = '';
  String esp32Ssid = '';
  String esp32WifiSsid = '';
  bool wifiConnected = false;
  String status = '';
  final ipController = TextEditingController(text: "192.168.4.1");

  // Agregar estas variables nuevas
  final passwordController = TextEditingController();
  bool obscurePassword = true;

  List<String> availableSSIDs = [];
  String? selectedSSID;
  String? currentSSID;
  bool isLoading = false;
  bool permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() {
      status = "Verificando permisos...";
    });

    // Solicitar permisos necesarios
    Map<Permission, PermissionStatus> permissions = await [
      Permission.location,
      Permission.locationWhenInUse,
    ].request();

    bool allGranted = permissions.values
        .every((status) => status == PermissionStatus.granted);

    if (allGranted) {
      setState(() {
        permissionsGranted = true;
      });
      await _initializeScreen();
    } else {
      setState(() {
        status = "Se requieren permisos de ubicación para escanear WiFi.\n"
            "Ve a Configuración > Aplicaciones > Gasox > Permisos y habilita Ubicación.";
      });

      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Permisos Requeridos"),
        content:
            const Text("Para configurar el WiFi del ESP32, necesitamos:\n\n"
                "• Acceso a ubicación (para escanear redes WiFi)\n"
                "• Acceso a WiFi\n\n"
                "Estos permisos son necesarios por las políticas de Android."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text("Abrir Configuración"),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeScreen() async {
    setState(() {
      status = "Inicializando...";
      isLoading = true;
    });

    await fetchEsp32Status();
    await scanNetworks();

    setState(() {
      isLoading = false;
    });
  }

  Future<void> fetchEsp32Status() async {
    try {
      setState(() {
        status = "Obteniendo estado del ESP32...";
      });

      final response = await http
          .get(
            Uri.parse("http://${ipController.text}/api/status"),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          esp32ApIp = data['network']?['ap']?['ip'] ?? '';
          esp32Ssid = data['network']?['ap']?['ssid'] ?? '';
          esp32WifiIp = data['network']?['wifi']?['ip'] ?? '';
          esp32WifiSsid = data['network']?['wifi']?['ssid'] ?? '';
          wifiConnected = data['network']?['wifi']?['connected'] ?? false;
          status = wifiConnected
              ? "✓ ESP32 conectado a: $esp32WifiSsid"
              : "ESP32 en modo AP únicamente";
        });
      } else {
        setState(() {
          status = "Error HTTP: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        status = "Error de conexión: ${e.toString()}\n"
            "¿Estás conectado a la red 'Gasox'?";
      });
      print("Error obteniendo estado: $e");
    }
  }

  Future<void> scanNetworks() async {
    try {
      setState(() {
        status = "Escaneando redes WiFi...";
        isLoading = true;
      });

      // Verificar permisos primero
      if (!permissionsGranted) {
        await _checkPermissions();
        if (!permissionsGranted) {
          setState(() {
            status = "No hay permisos para escanear redes";
            isLoading = false;
          });
          return;
        }
      }

      // Escanear redes
      List<WifiNetwork>? networks = await WiFiForIoTPlugin.loadWifiList();

      setState(() {
        if (networks != null && networks.isNotEmpty) {
          availableSSIDs =
              networks.map((network) => network.ssid ?? "").toList();
          availableSSIDs.removeWhere((ssid) => ssid.isEmpty);

          // Seleccionar red actual si está disponible
          if (currentSSID != null && availableSSIDs.contains(currentSSID)) {
            selectedSSID = currentSSID;
          } else if (availableSSIDs.isNotEmpty && selectedSSID == null) {
            selectedSSID = availableSSIDs.first;
          }

          status = availableSSIDs.isEmpty
              ? "No se encontraron redes WiFi"
              : "✓ Encontradas ${availableSSIDs.length} redes";
        } else {
          availableSSIDs = [];
          status = "No se encontraron redes WiFi";
        }
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        availableSSIDs = [];
        status = "Error escaneando redes: $e";
        isLoading = false;
      });
      print("Error escaneando redes: $e");
    }
  }

  Future<bool> _connectToEsp32AP() async {
    try {
      setState(() {
        status = "Conectando a red Gasox...";
      });

      // Intentar conectar a la red del ESP32
      bool connected = await WiFiForIoTPlugin.connect(
        "Gasox",
        password: "12345678",
        joinOnce: true,
        security: NetworkSecurity.WPA,
      );

      if (connected) {
        setState(() {
          status = "✓ Conectado a red Gasox";
        });

        // Esperar un poco para que la conexión se estabilice
        await Future.delayed(const Duration(seconds: 3));
        return true;
      } else {
        setState(() {
          status = "✗ No se pudo conectar a red Gasox automáticamente.\n"
              "Conéctate manualmente desde Configuración > WiFi";
        });
        return false;
      }
    } catch (e) {
      setState(() {
        status = "Error conectando a Gasox: $e";
      });
      return false;
    }
  }

  Future<void> connectToNetwork() async {
    if (selectedSSID == null || selectedSSID!.isEmpty) {
      setState(() {
        status = "Error: Selecciona una red WiFi";
      });
      return;
    }

    setState(() {
      status = "Enviando configuración WiFi...";
      isLoading = true;
    });

    try {
      print("Enviando configuración WiFi...");
      print("SSID: $selectedSSID");
      print("URL: http://${ipController.text}/api/wifi/configure");

      final response = await http
          .post(
            Uri.parse("http://${ipController.text}/api/wifi/configure"),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              "ssid": selectedSSID!,
              "password": passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 20));

      print("Respuesta HTTP: ${response.statusCode}");
      print("Cuerpo respuesta: ${response.body}");

      if (response.statusCode == 200) {
        setState(() {
          status = "✓ Configuración enviada correctamente!\n"
              "El ESP32 se está reiniciando...\n\n"
              "Próximos pasos:\n"
              "1. ⏱️ Espera 45 segundos\n"
              "2. 📱 Ve a WiFi y conéctate a '$selectedSSID'\n"
              "3. 🔄 Regresa y presiona 'Actualizar'\n"
              "4. ✅ Verifica la nueva IP del ESP32";
        });

        passwordController.clear();

        // Esperar más tiempo para el reinicio
        Future.delayed(const Duration(seconds: 45), () {
          if (mounted) {
            fetchEsp32Status();
          }
        });
      } else {
        setState(() {
          status =
              "❌ Error del servidor: ${response.statusCode}\n${response.body}";
        });
      }
    } catch (e) {
      print("Error en connectToNetwork: $e");
      setState(() {
        status = "❌ Error de conexión: $e\n\n"
            "Verifica:\n"
            "• Estás conectado a 'Gasox'\n"
            "• La IP es correcta (${ipController.text})\n"
            "• El ESP32 está encendido";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> forgetNetwork() async {
    // Confirmar acción
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirmar Acción"),
        content: const Text("¿Estás seguro de que quieres que el ESP32 olvide "
            "su configuración WiFi?\n\n"
            "Esto lo hará volver al modo de punto de acceso 'Gasox'."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Olvidar Red"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      status = "Eliminando configuración WiFi...";
      isLoading = true;
    });

    try {
      final response = await http
          .post(Uri.parse("http://${ipController.text}/api/wifi/forget"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          status =
              "✓ Configuración eliminada. ESP32 reiniciándose en modo AP...\n"
              "Reconéctate a la red 'Gasox' en 15 segundos.";
        });

        Future.delayed(const Duration(seconds: 20), () {
          if (mounted) {
            fetchEsp32Status();
          }
        });
      } else {
        setState(() {
          status = "Error eliminando configuración: ${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        status = "Error de red: ${e.toString()}";
      });
      print("Error olvidando red: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<bool> _testEsp32Connection() async {
    try {
      final response = await http
          .get(Uri.parse("http://${ipController.text}/api/status"))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text("Configuración Enviada"),
            ],
          ),
          content: Text(
              "El ESP32 se está reiniciando para conectarse a '$selectedSSID'.\n\n"
              "Pasos siguientes:\n"
              "1. ⏱️ Espera 30 segundos\n"
              "2. 📶 Conéctate a tu red WiFi '$selectedSSID'\n"
              "3. 🔄 Presiona 'Actualizar' para verificar\n"
              "4. 📝 Si muestra una nueva IP, úsala en la app\n\n"
              "Si no funciona:\n"
              "• Verifica la contraseña\n"
              "• Reconéctate a 'Gasox' y reintenta"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Entendido"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _refreshAll() async {
    if (!permissionsGranted) {
      await _checkPermissions();
    } else {
      await _initializeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Configuración de Red"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : _refreshAll,
            tooltip: "Actualizar",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Estado actual del ESP32
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.router, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          "Estado del ESP32",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                        "Red AP", esp32Ssid.isEmpty ? "Gasox" : esp32Ssid),
                    _buildInfoRow("IP del AP",
                        esp32ApIp.isEmpty ? "192.168.4.1" : esp32ApIp),
                    const Divider(height: 20),
                    Row(
                      children: [
                        Icon(
                          wifiConnected ? Icons.wifi : Icons.wifi_off,
                          color: wifiConnected ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "WiFi: ${wifiConnected ? 'Conectado' : 'Desconectado'}",
                          style: TextStyle(
                            color: wifiConnected ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (wifiConnected) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow("Red WiFi", esp32WifiSsid),
                      _buildInfoRow("IP WiFi", esp32WifiIp),
                      if (esp32WifiIp.isNotEmpty && esp32WifiIp != "0.0.0.0")
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.link),
                            label: const Text("Usar esta IP en la App"),
                            onPressed: () {
                              ipController.text = esp32WifiIp;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('IP actualizada a $esp32WifiIp'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              setState(() {});
                            },
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Configuración de IP
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.settings_ethernet,
                            color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text(
                          "IP del ESP32",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ipController,
                      decoration: const InputDecoration(
                        labelText: "Dirección IP",
                        hintText: "192.168.4.1",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.computer),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Configuración WiFi
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wifi, color: Colors.green),
                        const SizedBox(width: 8),
                        const Text(
                          "Configurar WiFi",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Selector de red
                    const Text("Selecciona la red WiFi:"),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedSSID,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.wifi_find),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: availableSSIDs
                          .map((ssid) => DropdownMenuItem(
                                value: ssid,
                                child: Text(
                                  ssid,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: isLoading
                          ? null
                          : (value) {
                              setState(() {
                                selectedSSID = value;
                              });
                            },
                      hint: const Text("Selecciona una red"),
                    ),

                    const SizedBox(height: 12),

                    // Campo de contraseña
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      enabled: !isLoading,
                      decoration: InputDecoration(
                        labelText: "Contraseña WiFi",
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Botones de acción
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isLoading ? null : connectToNetwork,
                            icon: isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi),
                            label: Text(
                                isLoading ? "Configurando..." : "Conectar"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isLoading ? null : forgetNetwork,
                            icon: const Icon(Icons.wifi_off),
                            label: const Text("Olvidar Red"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Estado y mensajes
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          status.contains("✓")
                              ? Icons.check_circle
                              : status.contains("Error") || status.contains("✗")
                                  ? Icons.error
                                  : Icons.info,
                          color: status.contains("✓")
                              ? Colors.green
                              : status.contains("Error") || status.contains("✗")
                                  ? Colors.red
                                  : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Estado",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      status.isEmpty ? "Listo para configurar" : status,
                      style: TextStyle(
                        color: status.contains("Error") || status.contains("✗")
                            ? Colors.red
                            : status.contains("✓")
                                ? Colors.green
                                : Colors.blue,
                      ),
                    ),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Botón de ayuda automática
            if (!wifiConnected && !isLoading)
              Card(
                color: Colors.orange.shade50,
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.help_outline,
                          size: 32, color: Colors.orange),
                      const SizedBox(height: 8),
                      const Text(
                        "¿Necesitas ayuda conectándote a 'Gasox'?",
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _connectToEsp32AP,
                        icon: const Icon(Icons.wifi),
                        label: const Text("Conectar a Gasox Automáticamente"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Instrucciones
            _buildInstructionsCard(),

            const SizedBox(height: 16),

            // Solución de problemas
            _buildTroubleshootingCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              "$label:",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? "N/A" : value,
              style: TextStyle(
                color: value.isEmpty ? Colors.grey : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      color: Colors.blue.shade50,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  "Instrucciones Paso a Paso",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              "1. 📶 Conéctate a la red 'Gasox' desde WiFi de tu teléfono\n"
              "2. 🔍 La app escaneará redes disponibles automáticamente\n"
              "3. 📋 Selecciona tu red WiFi doméstica de la lista\n"
              "4. 🔐 Ingresa la contraseña correcta y presiona 'Conectar'\n"
              "5. ⏱️ El ESP32 se reiniciará (espera 30 segundos)\n"
              "6. 📱 Conéctate a tu red WiFi normal\n"
              "7. 🔄 Presiona 'Actualizar' para obtener la nueva IP\n"
              "8. ✅ Usa la nueva IP del ESP32 en la aplicación",
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTroubleshootingCard() {
    return Card(
      color: Colors.orange.shade50,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  "Solución de Problemas",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              "🔍 No aparecen redes WiFi:\n"
              "  • Habilita permisos de ubicación\n"
              "  • Activa WiFi en tu teléfono\n"
              "  • Mantén presionado WiFi → Escanear\n\n"
              "❌ ESP32 no se conecta:\n"
              "  • Verifica que la contraseña sea correcta\n"
              "  • Asegúrate de que sea una red de 2.4GHz\n"
              "  • Evita caracteres especiales en la contraseña\n"
              "  • Reinicia el ESP32 si es necesario\n\n"
              "🔄 Error de conexión a ESP32:\n"
              "  • Asegúrate de estar conectado a 'Gasox'\n"
              "  • Verifica que la IP sea 192.168.4.1\n"
              "  • Desactiva datos móviles temporalmente\n"
              "  • Reinicia WiFi del teléfono\n\n"
              "🔧 Problemas persistentes:\n"
              "  • Presiona 'Olvidar Red' y reconfigura\n"
              "  • Verifica que el router esté en 2.4GHz\n"
              "  • Acércate al router WiFi\n"
              "  • Prueba con una red WiFi diferente",
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    ipController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
