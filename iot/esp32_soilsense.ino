#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Preferences.h>
#include <time.h>

const char* FIRESTORE_HOST = "firestore.googleapis.com";
const char* FIRESTORE_PATH = "/v1/projects/soilsense-db59e/databases/(default)/documents/soil_readings";
const char* DEVICE_STATUS_PATH = "/v1/projects/soilsense-db59e/databases/(default)/documents/system/device_status?updateMask.fieldPaths=online&updateMask.fieldPaths=setupMode&updateMask.fieldPaths=scanning&updateMask.fieldPaths=scanDurationSeconds&updateMask.fieldPaths=lastSeen&updateMask.fieldPaths=rssi&updateMask.fieldPaths=hardwareFingerprint";
const char* DEVICE_ASSIGNMENT_PATH = "/v1/projects/soilsense-db59e/databases/(default)/documents/system/device_assignment?mask.fieldPaths=currentOwnerUid";
const char* SCAN_SETTINGS_PATH = "/v1/projects/soilsense-db59e/databases/(default)/documents/system/scan_settings?mask.fieldPaths=durationSeconds";
const char* FIRMWARE_VERSION = "3.9.2-hybrid-wifi";

constexpr int RS485_RX_PIN = 16;
constexpr int RS485_TX_PIN = 17;
constexpr int SCAN_BUTTON_PIN = 27;
constexpr int STOP_BUTTON_PIN = 14;
constexpr int BLUE_LED_PIN = 25;
constexpr int YELLOW_LED_PIN = 26;
constexpr int GREEN_LED_PIN = 33;
constexpr int RED_LED_PIN = 32;
constexpr bool RS485_AUTO_DIRECTION = true;
constexpr int RS485_DE_RE_PIN = 4;
constexpr uint32_t RS485_BAUD_RATE = 4800;
constexpr uint8_t MODBUS_SLAVE_ID = 0x01;
constexpr uint8_t MODBUS_FUNCTION = 0x03;
constexpr uint16_t START_REGISTER = 0x0000;
constexpr uint16_t REGISTER_COUNT = 7;
constexpr uint8_t MOISTURE_REGISTER_INDEX = 0;
constexpr uint8_t TEMPERATURE_REGISTER_INDEX = 1;
constexpr uint8_t EC_REGISTER_INDEX = 2;
constexpr uint8_t PH_REGISTER_INDEX = 3;
constexpr uint8_t NITROGEN_REGISTER_INDEX = 4;
constexpr uint8_t PHOSPHORUS_REGISTER_INDEX = 5;
constexpr uint8_t POTASSIUM_REGISTER_INDEX = 6;
constexpr float MOISTURE_SCALE = 0.1f;
constexpr float TEMPERATURE_SCALE = 0.1f;
constexpr float PH_SCALE = 0.1f;
constexpr float NITROGEN_SCALE = 1.0f;
constexpr float PHOSPHORUS_SCALE = 1.0f;
constexpr float POTASSIUM_SCALE = 1.0f;
constexpr unsigned long SENSOR_TIMEOUT_MS = 1200;
constexpr unsigned long WIFI_TIMEOUT_MS = 20000;
constexpr unsigned long WIFI_RECONNECT_INTERVAL_MS = 10000;
constexpr unsigned long CLOCK_TIMEOUT_MS = 15000;
constexpr unsigned long HTTPS_TIMEOUT_MS = 12000;
constexpr unsigned long DEVICE_STATUS_HTTPS_TIMEOUT_MS = 3000;
constexpr uint8_t HTTPS_RETRY_COUNT = 3;
constexpr unsigned long DEFAULT_SCAN_DURATION_MS = 120000;
constexpr unsigned long MIN_SCAN_DURATION_MS = 30000;
constexpr unsigned long MAX_SCAN_DURATION_MS = 300000;
constexpr unsigned long SAMPLE_INTERVAL_MS = 500;
constexpr unsigned long BUTTON_DEBOUNCE_MS = 25;
constexpr unsigned long BUTTON_LONG_PRESS_MS = 3000;
constexpr unsigned long PROVISIONING_TIMEOUT_MS = 180000;
constexpr unsigned long DEVICE_STATUS_INTERVAL_MS = 8000;
constexpr unsigned long DEVICE_STATUS_RETRY_INTERVAL_MS = 1500;
constexpr unsigned long GREEN_SUCCESS_MS = 3000;
constexpr unsigned long RED_ERROR_BLINK_MS = 90;
constexpr unsigned long YELLOW_ACTIVITY_PULSE_MS = 85;
constexpr unsigned long YELLOW_START_SOLID_MS = 1500;
constexpr unsigned long APP_STATE_SETTLE_MS = 550;

struct SoilReading {
  float moisture;
  float temperature;
  uint16_t electricalConductivity;
  float ph;
  float nitrogen;
  float phosphorus;
  float potassium;
  bool valid;
};

struct ScanAccumulator {
  double moisture;
  double temperature;
  uint32_t electricalConductivity;
  double ph;
  double nitrogen;
  double phosphorus;
  double potassium;
  uint16_t samples;
};

struct HttpsResponse {
  int status;
  String body;
};

HttpsResponse readHttpsResponse(WiFiClientSecure& client);

Preferences wifiStorage;
String savedWifiSsid;
String savedWifiPassword;
// Snapshot of the working credentials before Wi-Fi setup begins. These are
// kept until the replacement network has connected successfully so a cancelled
// or failed setup can safely return to the previous Wi-Fi.
String wifiBeforeProvisioningSsid;
String wifiBeforeProvisioningPassword;
String cachedOwnerUid;
ScanAccumulator scanTotals{};
volatile bool scanning = false;
volatile bool scanIndicatorActive = false;
volatile bool scanSolidIndicatorActive = false;
volatile bool provisioningActive = false;
bool smartConfigHandled = false;
unsigned long scanStartedAt = 0;
unsigned long activeScanDurationMs = DEFAULT_SCAN_DURATION_MS;
unsigned long lastSampleFinishedAt = 0;
unsigned long provisioningStartedAt = 0;
unsigned long lastDeviceStatusAt = 0;
unsigned long lastDeviceStatusAttemptAt = 0;
bool lastDeviceStatusSucceeded = false;
unsigned long lastWifiReconnectAttemptAt = 0;
volatile unsigned long greenLedUntil = 0;
volatile unsigned long redErrorUntil = 0;
volatile unsigned long yellowActivityUntil = 0;
volatile bool shortPressRequested = false;
volatile bool longPressRequested = false;
volatile bool stopPressRequested = false;
volatile bool stopLongPressRequested = false;
TaskHandle_t indicatorButtonTaskHandle = nullptr;

bool ensureClock();
bool sendDeviceStatus(bool setupMode);
void serviceWifiReconnect();
void startWifiProvisioning();
void cancelWifiProvisioning();
void startScan();
void cancelScan();
bool refreshScanDuration();
bool openFirestoreTls(WiFiClientSecure& client);

void signalError(unsigned long durationMs = 6000) {
  redErrorUntil = millis() + durationMs;
}

void signalSuccess(unsigned long durationMs = GREEN_SUCCESS_MS) {
  greenLedUntil = millis() + durationMs;
}

void markRs485Activity() {
  yellowActivityUntil = millis() + YELLOW_ACTIVITY_PULSE_MS;
}

void indicatorButtonTask(void* parameter) {
  bool rawStartButton = HIGH;
  bool stableStartButton = HIGH;
  bool previousRawStartButton = HIGH;
  bool longPressHandled = false;
  unsigned long startRawChangedAt = 0;
  unsigned long startPressedAt = 0;

  bool rawStopButton = HIGH;
  bool stableStopButton = HIGH;
  bool previousRawStopButton = HIGH;
  bool stopLongPressHandled = false;
  unsigned long stopRawChangedAt = 0;
  unsigned long stopPressedAt = 0;

  bool redState = true;
  unsigned long lastRedToggleAt = 0;

  for (;;) {
    const unsigned long now = millis();

    rawStartButton = digitalRead(SCAN_BUTTON_PIN);
    if (rawStartButton != previousRawStartButton) {
      previousRawStartButton = rawStartButton;
      startRawChangedAt = now;
    }

    if (now - startRawChangedAt >= BUTTON_DEBOUNCE_MS && rawStartButton != stableStartButton) {
      stableStartButton = rawStartButton;

      if (stableStartButton == LOW) {
        startPressedAt = now;
        longPressHandled = false;
      } else if (!longPressHandled && now - startPressedAt >= BUTTON_DEBOUNCE_MS) {
        shortPressRequested = true;
      }
    }

    if (stableStartButton == LOW && !longPressHandled && now - startPressedAt >= BUTTON_LONG_PRESS_MS) {
      longPressHandled = true;
      longPressRequested = true;
      shortPressRequested = false;
    }

    rawStopButton = digitalRead(STOP_BUTTON_PIN);
    if (rawStopButton != previousRawStopButton) {
      previousRawStopButton = rawStopButton;
      stopRawChangedAt = now;
    }

    if (now - stopRawChangedAt >= BUTTON_DEBOUNCE_MS && rawStopButton != stableStopButton) {
      stableStopButton = rawStopButton;
      if (stableStopButton == LOW) {
        stopPressedAt = now;
        stopLongPressHandled = false;
        // A normal STOP press cancels an active soil scan immediately. During
        // Wi-Fi setup this short press has no effect; holding for 3 seconds is
        // required so setup is not cancelled accidentally.
        stopPressRequested = true;
      }
    }

    if (stableStopButton == LOW && !stopLongPressHandled && now - stopPressedAt >= BUTTON_LONG_PRESS_MS) {
      stopLongPressHandled = true;
      stopLongPressRequested = true;
    }

    digitalWrite(BLUE_LED_PIN, provisioningActive ? HIGH : LOW);

    const bool yellowBlink = scanIndicatorActive && ((now / 300UL) % 2UL == 0UL);
    const bool yellowActive = scanSolidIndicatorActive || yellowBlink;
    digitalWrite(YELLOW_LED_PIN, yellowActive ? HIGH : LOW);

    const bool greenActive = greenLedUntil != 0 && static_cast<long>(greenLedUntil - now) > 0;
    digitalWrite(GREEN_LED_PIN, greenActive ? HIGH : LOW);
    if (!greenActive) greenLedUntil = 0;

    const bool errorActive = redErrorUntil != 0 && static_cast<long>(redErrorUntil - now) > 0;
    if (errorActive) {
      if (lastRedToggleAt == 0 || now - lastRedToggleAt >= RED_ERROR_BLINK_MS) {
        lastRedToggleAt = now;
        redState = !redState;
      }
      digitalWrite(RED_LED_PIN, redState ? HIGH : LOW);
    } else {
      redErrorUntil = 0;
      redState = true;
      lastRedToggleAt = 0;
      digitalWrite(RED_LED_PIN, HIGH);
    }

    vTaskDelay(pdMS_TO_TICKS(5));
  }
}

void serviceButtonEvents() {
  if (stopLongPressRequested) {
    stopLongPressRequested = false;
    stopPressRequested = false;

    if (provisioningActive) {
      cancelWifiProvisioning();
    } else if (scanning) {
      // The initial press already requests an immediate scan cancellation, but
      // keep this fallback for the unlikely case the main loop was busy.
      cancelScan();
    }
  }

  if (stopPressRequested) {
    stopPressRequested = false;
    if (scanning) cancelScan();
  }

  if (longPressRequested) {
    longPressRequested = false;
    shortPressRequested = false;
    if (!scanning && !provisioningActive) startWifiProvisioning();
  }

  if (shortPressRequested) {
    shortPressRequested = false;
    if (!scanning && !provisioningActive) startScan();
  }
}

uint16_t modbusCrc(const uint8_t* data, size_t length) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < length; i++) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; bit++) {
      crc = (crc & 1) ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc;
}

void setRs485Transmit(bool enabled) {
  if (RS485_AUTO_DIRECTION) return;
  digitalWrite(RS485_DE_RE_PIN, enabled ? HIGH : LOW);
  delay(2);
}

bool readModbusRegisters(uint16_t* registers, size_t count) {
  if (count != REGISTER_COUNT) return false;

  uint8_t request[8] = {
    MODBUS_SLAVE_ID,
    MODBUS_FUNCTION,
    static_cast<uint8_t>(START_REGISTER >> 8),
    static_cast<uint8_t>(START_REGISTER & 0xFF),
    static_cast<uint8_t>(REGISTER_COUNT >> 8),
    static_cast<uint8_t>(REGISTER_COUNT & 0xFF),
    0,
    0
  };

  const uint16_t requestCrc = modbusCrc(request, 6);
  request[6] = requestCrc & 0xFF;
  request[7] = requestCrc >> 8;

  while (Serial2.available()) Serial2.read();

  setRs485Transmit(true);
  markRs485Activity();
  Serial2.write(request, sizeof(request));
  Serial2.flush();
  setRs485Transmit(false);

  constexpr size_t RESPONSE_SIZE = 5 + REGISTER_COUNT * 2;
  constexpr size_t RECEIVE_BUFFER_SIZE = 48;
  uint8_t receiveBuffer[RECEIVE_BUFFER_SIZE] = {};
  size_t receivedCount = 0;
  const unsigned long startedAt = millis();

  while (millis() - startedAt < SENSOR_TIMEOUT_MS) {
    while (Serial2.available()) {
      const int value = Serial2.read();
      if (value >= 0 && receivedCount < RECEIVE_BUFFER_SIZE) {
        if (receivedCount == 0) markRs485Activity();
        receiveBuffer[receivedCount++] = static_cast<uint8_t>(value);
      }
    }
    delay(1);
  }

  for (size_t frameStart = 0; frameStart + RESPONSE_SIZE <= receivedCount; frameStart++) {
    const uint8_t* response = &receiveBuffer[frameStart];
    if (response[0] != MODBUS_SLAVE_ID || response[1] != MODBUS_FUNCTION || response[2] != REGISTER_COUNT * 2) continue;

    const uint16_t expectedCrc = modbusCrc(response, RESPONSE_SIZE - 2);
    const uint16_t receivedCrc = response[RESPONSE_SIZE - 2] | (static_cast<uint16_t>(response[RESPONSE_SIZE - 1]) << 8);
    if (expectedCrc != receivedCrc) continue;

    for (size_t index = 0; index < REGISTER_COUNT; index++) {
      const size_t offset = 3 + index * 2;
      registers[index] = (static_cast<uint16_t>(response[offset]) << 8) | response[offset + 1];
    }
    return true;
  }

  Serial.print("Sensor bytes received: ");
  Serial.println(receivedCount);
  if (receivedCount > 0) {
    Serial.print("Raw sensor response: ");
    for (size_t index = 0; index < receivedCount; index++) {
      if (receiveBuffer[index] < 0x10) Serial.print('0');
      Serial.print(receiveBuffer[index], HEX);
      Serial.print(' ');
    }
    Serial.println();
  }

  return false;
}

SoilReading readAllSensors() {
  SoilReading reading{};
  uint16_t registers[REGISTER_COUNT] = {};

  if (!readModbusRegisters(registers, REGISTER_COUNT)) {
    reading.valid = false;
    return reading;
  }

  reading.moisture = registers[MOISTURE_REGISTER_INDEX] * MOISTURE_SCALE;
  reading.temperature = static_cast<int16_t>(registers[TEMPERATURE_REGISTER_INDEX]) * TEMPERATURE_SCALE;
  reading.electricalConductivity = registers[EC_REGISTER_INDEX];
  reading.ph = registers[PH_REGISTER_INDEX] * PH_SCALE;
  reading.nitrogen = registers[NITROGEN_REGISTER_INDEX] * NITROGEN_SCALE;
  reading.phosphorus = registers[PHOSPHORUS_REGISTER_INDEX] * PHOSPHORUS_SCALE;
  reading.potassium = registers[POTASSIUM_REGISTER_INDEX] * POTASSIUM_SCALE;

  reading.valid =
    isfinite(reading.moisture) && reading.moisture >= 0 && reading.moisture <= 100 &&
    isfinite(reading.temperature) && reading.temperature >= -30 && reading.temperature <= 80 &&
    reading.electricalConductivity <= 50000 &&
    isfinite(reading.ph) && reading.ph >= 0 && reading.ph <= 14 &&
    isfinite(reading.nitrogen) && reading.nitrogen >= 0 && reading.nitrogen <= 2000 &&
    isfinite(reading.phosphorus) && reading.phosphorus >= 0 && reading.phosphorus <= 2000 &&
    isfinite(reading.potassium) && reading.potassium >= 0 && reading.potassium <= 3000;

  return reading;
}

bool ensureWifi() {
  if (WiFi.status() == WL_CONNECTED) return true;
  if (savedWifiSsid.isEmpty()) return false;

  Serial.print("Connecting to saved Wi-Fi: ");
  Serial.println(savedWifiSsid);

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(savedWifiSsid.c_str(), savedWifiPassword.c_str());

  const unsigned long startedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startedAt < WIFI_TIMEOUT_MS) delay(250);

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Wi-Fi connected. IP: ");
    Serial.println(WiFi.localIP());
    return true;
  }

  Serial.println("Saved Wi-Fi connection failed.");
  return false;
}

void serviceWifiReconnect() {
  // Hybrid Wi-Fi behavior:
  // - If no credentials are saved, setup starts automatically in setup().
  // - If saved credentials exist but the network is temporarily unavailable,
  //   stay in normal mode with the blue LED OFF and retry in the background.
  // - The user can hold START for 3 seconds at any time to intentionally
  //   enter Wi-Fi setup and choose a different network.
  if (provisioningActive || savedWifiSsid.isEmpty() || WiFi.status() == WL_CONNECTED) return;

  const unsigned long now = millis();
  if (lastWifiReconnectAttemptAt != 0 && now - lastWifiReconnectAttemptAt < WIFI_RECONNECT_INTERVAL_MS) return;
  lastWifiReconnectAttemptAt = now;

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);

  Serial.print("Saved Wi-Fi unavailable; retrying in background: ");
  Serial.println(savedWifiSsid);
  Serial.println("Hold START for 3 seconds only if you want to change Wi-Fi.");

  // Non-blocking reconnect attempt. The blue LED remains OFF because
  // provisioningActive is false.
  WiFi.reconnect();
}

bool reconnectPreviousWifiAfterProvisioning() {
  if (wifiBeforeProvisioningSsid.isEmpty()) {
    WiFi.setAutoReconnect(false);
    WiFi.disconnect(true, true);
    Serial.println("No previous Wi-Fi was available to restore.");
    return false;
  }

  savedWifiSsid = wifiBeforeProvisioningSsid;
  savedWifiPassword = wifiBeforeProvisioningPassword;

  WiFi.stopSmartConfig();
  WiFi.disconnect(false, false);
  delay(150);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(savedWifiSsid.c_str(), savedWifiPassword.c_str());

  const unsigned long startedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startedAt < WIFI_TIMEOUT_MS) {
    delay(50);
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Previous Wi-Fi could not be restored.");
    return false;
  }

  Serial.print("Previous Wi-Fi restored: ");
  Serial.println(savedWifiSsid);
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());
  return true;
}

void stopWifiProvisioning() {
  if (!provisioningActive) return;
  WiFi.stopSmartConfig();
  provisioningActive = false;
  smartConfigHandled = false;
  Serial.println("SmartConfig Wi-Fi setup stopped.");
}

void cancelWifiProvisioning() {
  if (!provisioningActive) return;

  // Turn the blue LED off immediately. The indicator task follows this flag.
  provisioningActive = false;
  smartConfigHandled = false;
  WiFi.stopSmartConfig();

  Serial.println();
  Serial.println("==================================");
  Serial.println("WI-FI SETUP CANCELLED BY STOP BUTTON");
  Serial.println("The pending Wi-Fi setup was discarded.");

  const bool restored = reconnectPreviousWifiAfterProvisioning();
  if (restored) {
    sendDeviceStatus(false);
    refreshScanDuration();
    signalSuccess(1400);
    Serial.println("Previous Wi-Fi remains active. Hold START 3 seconds to try setup again.");
  } else {
    signalError();
    Serial.println("Device is not connected. Hold START 3 seconds when you are ready to set up Wi-Fi.");
  }
  Serial.println("==================================");
}

void startWifiProvisioning() {
  if (scanning || provisioningActive) return;

  // Keep a snapshot of the last working credentials. They are not erased when
  // setup begins; they are replaced only after the new network succeeds.
  wifiBeforeProvisioningSsid = savedWifiSsid;
  wifiBeforeProvisioningPassword = savedWifiPassword;

  provisioningActive = true;
  smartConfigHandled = false;
  provisioningStartedAt = millis();

  if (WiFi.status() == WL_CONNECTED) {
    sendDeviceStatus(true);
  }

  WiFi.setAutoReconnect(false);
  WiFi.stopSmartConfig();
  WiFi.disconnect(true, true);
  delay(350);

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(false);
  delay(150);

  if (!WiFi.beginSmartConfig(SC_TYPE_ESPTOUCH)) {
    provisioningActive = false;
    smartConfigHandled = false;
    Serial.println("ERROR: Could not start SmartConfig / ESPTouch.");
    if (reconnectPreviousWifiAfterProvisioning()) {
      sendDeviceStatus(false);
      Serial.println("Previous Wi-Fi restored after setup failed to start.");
    }
    signalError();
    return;
  }

  Serial.println();
  Serial.println("==================================");
  Serial.println("SMARTCONFIG WI-FI SETUP ACTIVE");
  Serial.println("Previous saved Wi-Fi is protected until the new setup succeeds.");
  Serial.println("Keep the phone on the target 2.4 GHz Wi-Fi.");
  Serial.println("Open SoilSense > Profile > SoilSense Wi-Fi Setup.");
  Serial.println("Enter the new Wi-Fi name/password and send the settings.");
  Serial.println("No Bluetooth. No account pairing.");
  Serial.println("Hold STOP 3 seconds to cancel setup and return to the previous Wi-Fi.");
  Serial.println("==================================");
}

bool stabilizeWifiAfterSmartConfig() {
  WiFi.stopSmartConfig();
  smartConfigHandled = false;
  delay(150);
  WiFi.disconnect(false, false);
  delay(150);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(savedWifiSsid.c_str(), savedWifiPassword.c_str());

  const unsigned long startedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startedAt < WIFI_TIMEOUT_MS) {
    delay(50);
  }

  if (WiFi.status() != WL_CONNECTED) {
    provisioningActive = false;
    Serial.println("Wi-Fi did not reconnect after SmartConfig.");
    signalError();
    return false;
  }

  provisioningActive = false;
  Serial.print("Wi-Fi ready. IP: ");
  Serial.println(WiFi.localIP());
  Serial.print("Gateway: ");
  Serial.println(WiFi.gatewayIP());
  Serial.print("DNS: ");
  Serial.println(WiFi.dnsIP());
  return true;
}

void serviceWifiProvisioning() {
  if (!provisioningActive) return;

  if (!smartConfigHandled && WiFi.smartConfigDone()) {
    smartConfigHandled = true;
    Serial.println("SmartConfig received Wi-Fi credentials.");

    const unsigned long startedAt = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startedAt < WIFI_TIMEOUT_MS) {
      if (stopLongPressRequested) {
        stopLongPressRequested = false;
        stopPressRequested = false;
        cancelWifiProvisioning();
        return;
      }
      delay(50);
    }

    if (WiFi.status() == WL_CONNECTED) {
      const String candidateWifiSsid = WiFi.SSID();
      const String candidateWifiPassword = WiFi.psk();
      savedWifiSsid = candidateWifiSsid;
      savedWifiPassword = candidateWifiPassword;

      Serial.print("Wi-Fi credentials received for: ");
      Serial.println(candidateWifiSsid);
      Serial.print("IP address: ");
      Serial.println(WiFi.localIP());

      if (stabilizeWifiAfterSmartConfig()) {
        // Commit only after the replacement Wi-Fi has proven it can reconnect.
        wifiStorage.putString("ssid", savedWifiSsid);
        wifiStorage.putString("password", savedWifiPassword);
        wifiBeforeProvisioningSsid = savedWifiSsid;
        wifiBeforeProvisioningPassword = savedWifiPassword;
        const bool statusSynced = sendDeviceStatus(false);
        if (!statusSynced) {
          Serial.println("Wi-Fi is connected, but the first mobile heartbeat sync failed; retrying automatically.");
        }
        signalSuccess(1400);
        Serial.println("Wi-Fi setup complete and saved. Press START to scan.");
      } else {
        Serial.println("New Wi-Fi could not be stabilized. Restoring the previous Wi-Fi.");
        savedWifiSsid = wifiBeforeProvisioningSsid;
        savedWifiPassword = wifiBeforeProvisioningPassword;
        if (reconnectPreviousWifiAfterProvisioning()) {
          sendDeviceStatus(false);
          Serial.println("Previous Wi-Fi restored. Hold START 3 seconds to retry setup.");
        } else {
          Serial.println("No working previous Wi-Fi could be restored.");
        }
      }
      return;
    }

    Serial.println("Wi-Fi credentials were received, but connection failed.");
    stopWifiProvisioning();
    if (reconnectPreviousWifiAfterProvisioning()) {
      sendDeviceStatus(false);
      Serial.println("Previous Wi-Fi restored. Hold START 3 seconds to try setup again.");
    } else {
      Serial.println("No working previous Wi-Fi is available. Hold START 3 seconds and try setup again.");
    }
    signalError();
    return;
  }

  if (millis() - provisioningStartedAt >= PROVISIONING_TIMEOUT_MS) {
    Serial.println("SmartConfig setup timed out.");
    stopWifiProvisioning();
    if (reconnectPreviousWifiAfterProvisioning()) {
      sendDeviceStatus(false);
      Serial.println("Previous Wi-Fi restored. Hold START 3 seconds to try setup again.");
    } else {
      Serial.println("No working previous Wi-Fi is available. Hold START 3 seconds and try setup again.");
    }
    signalError();
  }
}

bool ensureClock() {
  if (time(nullptr) > 1700000000) return true;

  configTime(0, 0, "pool.ntp.org", "time.google.com", "time.cloudflare.com");
  const unsigned long startedAt = millis();

  while (time(nullptr) <= 1700000000 && millis() - startedAt < CLOCK_TIMEOUT_MS) delay(250);
  return time(nullptr) > 1700000000;
}

String hardwareFingerprint() {
  const uint64_t chip = ESP.getEfuseMac();
  char fingerprint[13];
  snprintf(
    fingerprint,
    sizeof(fingerprint),
    "%04X%08X",
    static_cast<uint16_t>(chip >> 32),
    static_cast<uint32_t>(chip)
  );
  return String(fingerprint);
}

String firestoreTimestamp() {
  const time_t now = time(nullptr);
  struct tm utcTime = {};
  gmtime_r(&now, &utcTime);
  char timestamp[25];
  strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &utcTime);
  return String(timestamp);
}

String buildDeviceStatusBody(bool setupMode) {
  String body;
  body.reserve(500);
  body = "{\"fields\":{";
  body += "\"online\":{\"booleanValue\":" + String(setupMode ? "false" : "true") + "},";
  body += "\"setupMode\":{\"booleanValue\":" + String(setupMode ? "true" : "false") + "},";
  body += "\"scanning\":{\"booleanValue\":" + String(scanning ? "true" : "false") + "},";
  body += "\"scanDurationSeconds\":{\"integerValue\":\"" + String(activeScanDurationMs / 1000UL) + "\"},";
  body += "\"lastSeen\":{\"timestampValue\":\"" + firestoreTimestamp() + "\"},";
  body += "\"rssi\":{\"integerValue\":\"" + String(WiFi.RSSI()) + "\"},";
  body += "\"hardwareFingerprint\":{\"stringValue\":\"" + hardwareFingerprint() + "\"}";
  body += "}}";
  return body;
}

bool sendDeviceStatus(bool setupMode) {
  if (WiFi.status() != WL_CONNECTED) {
    lastDeviceStatusSucceeded = false;
    return false;
  }
  lastDeviceStatusAttemptAt = millis();
  lastDeviceStatusSucceeded = false;
  if (!ensureClock()) return false;

  WiFiClientSecure client;
  client.setInsecure();
  client.setHandshakeTimeout(3);
  client.setTimeout(DEVICE_STATUS_HTTPS_TIMEOUT_MS);

  if (!client.connect(FIRESTORE_HOST, 443)) return false;

  const String body = buildDeviceStatusBody(setupMode);

  client.print("PATCH ");
  client.print(DEVICE_STATUS_PATH);
  client.println(" HTTP/1.1");
  client.print("Host: ");
  client.println(FIRESTORE_HOST);
  client.println("Content-Type: application/json");
  client.println("Accept: application/json");
  client.println("Connection: close");
  client.print("Content-Length: ");
  client.println(body.length());
  client.println();
  client.print(body);

  const unsigned long startedAt = millis();
  while (!client.available() && client.connected() && millis() - startedAt < DEVICE_STATUS_HTTPS_TIMEOUT_MS) {
    if (shortPressRequested || longPressRequested || stopPressRequested || stopLongPressRequested) {
      client.stop();
      return false;
    }
    delay(5);
  }

  if (!client.available()) {
    client.stop();
    return false;
  }

  String statusLine = client.readStringUntil('\n');
  statusLine.trim();

  int status = -1;
  const int firstSpace = statusLine.indexOf(' ');
  if (firstSpace >= 0 && statusLine.length() >= firstSpace + 4) {
    status = statusLine.substring(firstSpace + 1, firstSpace + 4).toInt();
  }

  client.stop();

  if (status == 200) {
    lastDeviceStatusAt = millis();
    lastDeviceStatusSucceeded = true;
    Serial.println(setupMode ? "Mobile Wi-Fi setup automatically enabled." : "Device online status updated.");
    return true;
  }

  Serial.print("Device status update failed: ");
  Serial.println(statusLine);
  return false;
}

void serviceDeviceStatus() {
  if (provisioningActive || shortPressRequested || longPressRequested || stopPressRequested || stopLongPressRequested || WiFi.status() != WL_CONNECTED) return;

  // After Wi-Fi setup/reconnect, retry a failed Firestore heartbeat quickly so
  // the mobile app does not remain stuck in an offline state. Once a heartbeat
  // succeeds, return to the normal 8-second interval.
  const unsigned long interval = lastDeviceStatusSucceeded
      ? DEVICE_STATUS_INTERVAL_MS
      : DEVICE_STATUS_RETRY_INTERVAL_MS;
  if (lastDeviceStatusAttemptAt != 0 && millis() - lastDeviceStatusAttemptAt < interval) return;
  sendDeviceStatus(false);
}

bool waitForHttpsData(WiFiClientSecure& client, unsigned long timeoutMs) {
  const unsigned long startedAt = millis();
  while (!client.available() && client.connected() && millis() - startedAt < timeoutMs) {
    delay(2);
  }
  return client.available();
}

bool readExactBytes(WiFiClientSecure& client, String& output, size_t byteCount, unsigned long timeoutMs) {
  output.reserve(output.length() + byteCount);
  size_t received = 0;
  unsigned long lastDataAt = millis();

  while (received < byteCount && millis() - lastDataAt < timeoutMs) {
    while (client.available() && received < byteCount) {
      output += static_cast<char>(client.read());
      received++;
      lastDataAt = millis();
    }

    if (!client.connected() && !client.available()) break;
    delay(1);
  }

  return received == byteCount;
}

HttpsResponse readHttpsResponse(WiFiClientSecure& client) {
  HttpsResponse result{-1, ""};

  if (!waitForHttpsData(client, HTTPS_TIMEOUT_MS)) return result;

  String statusLine = client.readStringUntil('\n');
  statusLine.trim();

  const int firstSpace = statusLine.indexOf(' ');
  if (firstSpace >= 0 && statusLine.length() >= firstSpace + 4) {
    result.status = statusLine.substring(firstSpace + 1, firstSpace + 4).toInt();
  }

  int contentLength = -1;
  bool chunked = false;

  while (client.connected() || client.available()) {
    if (!client.available() && !waitForHttpsData(client, 2500)) break;
    String line = client.readStringUntil('\n');
    line.trim();
    if (line.isEmpty()) break;

    String lower = line;
    lower.toLowerCase();

    if (lower.startsWith("content-length:")) {
      String value = line.substring(line.indexOf(':') + 1);
      value.trim();
      contentLength = value.toInt();
    } else if (lower.startsWith("transfer-encoding:") && lower.indexOf("chunked") >= 0) {
      chunked = true;
    }
  }

  if (chunked) {
    while (client.connected() || client.available()) {
      if (!client.available() && !waitForHttpsData(client, 2500)) break;

      String sizeLine = client.readStringUntil('\n');
      sizeLine.trim();
      const int semicolon = sizeLine.indexOf(';');
      if (semicolon >= 0) sizeLine = sizeLine.substring(0, semicolon);

      const size_t chunkSize = strtoul(sizeLine.c_str(), nullptr, 16);
      if (chunkSize == 0) {
        while (client.connected() || client.available()) {
          if (!client.available() && !waitForHttpsData(client, 500)) break;
          String trailer = client.readStringUntil('\n');
          trailer.trim();
          if (trailer.isEmpty()) break;
        }
        break;
      }

      if (!readExactBytes(client, result.body, chunkSize, 3000)) break;

      for (uint8_t i = 0; i < 2; i++) {
        if (!client.available() && !waitForHttpsData(client, 1000)) break;
        if (client.available()) client.read();
      }
    }
  } else if (contentLength >= 0) {
    readExactBytes(client, result.body, static_cast<size_t>(contentLength), 4000);
  } else {
    unsigned long lastDataAt = millis();
    while ((client.connected() || client.available()) && millis() - lastDataAt < 1200) {
      while (client.available()) {
        result.body += static_cast<char>(client.read());
        lastDataAt = millis();
      }
      delay(1);
    }
  }

  return result;
}

String firestoreStringField(const String& json, const String& fieldName) {
  const String fieldMarker = "\"" + fieldName + "\"";
  const int fieldPosition = json.indexOf(fieldMarker);
  if (fieldPosition < 0) return "";

  const int stringValuePosition = json.indexOf("\"stringValue\"", fieldPosition);
  if (stringValuePosition < 0) return "";

  const int colonPosition = json.indexOf(':', stringValuePosition);
  if (colonPosition < 0) return "";

  const int firstQuote = json.indexOf('"', colonPosition + 1);
  if (firstQuote < 0) return "";

  const int secondQuote = json.indexOf('"', firstQuote + 1);
  if (secondQuote < 0) return "";

  return json.substring(firstQuote + 1, secondQuote);
}

long firestoreIntegerField(const String& json, const String& fieldName, long fallbackValue) {
  const String fieldMarker = "\"" + fieldName + "\"";
  const int fieldPosition = json.indexOf(fieldMarker);
  if (fieldPosition < 0) return fallbackValue;

  const int integerValuePosition = json.indexOf("\"integerValue\"", fieldPosition);
  if (integerValuePosition < 0) return fallbackValue;

  const int colonPosition = json.indexOf(':', integerValuePosition);
  if (colonPosition < 0) return fallbackValue;

  int valueStart = colonPosition + 1;
  while (valueStart < json.length() && (json[valueStart] == ' ' || json[valueStart] == '"')) valueStart++;

  int valueEnd = valueStart;
  while (valueEnd < json.length() && isDigit(json[valueEnd])) valueEnd++;
  if (valueEnd <= valueStart) return fallbackValue;

  return json.substring(valueStart, valueEnd).toInt();
}

bool refreshScanDuration() {
  WiFiClientSecure client;
  if (!openFirestoreTls(client)) {
    Serial.println("Scan duration lookup failed; using the last/default duration.");
    return false;
  }

  client.print("GET ");
  client.print(SCAN_SETTINGS_PATH);
  client.println(" HTTP/1.1");
  client.print("Host: ");
  client.println(FIRESTORE_HOST);
  client.println("Accept: application/json");
  client.println("User-Agent: SoilSense-ESP32");
  client.println("Connection: close");
  client.println();

  HttpsResponse response = readHttpsResponse(client);
  client.stop();

  if (response.status == 404) {
    activeScanDurationMs = DEFAULT_SCAN_DURATION_MS;
    Serial.println("No scan setting found; using 2 minutes.");
    return true;
  }

  if (response.status != 200) {
    Serial.printf("Scan duration lookup failed: HTTP %d. Using current duration.\n", response.status);
    return false;
  }

  long seconds = firestoreIntegerField(
    response.body,
    "durationSeconds",
    static_cast<long>(DEFAULT_SCAN_DURATION_MS / 1000UL)
  );
  seconds = constrain(seconds, 30L, 300L);
  activeScanDurationMs = static_cast<unsigned long>(seconds) * 1000UL;
  Serial.printf("Scan duration loaded: %ld seconds.\n", seconds);
  return true;
}

bool openFirestoreTls(WiFiClientSecure& client) {
  if (!ensureWifi()) return false;

  client.stop();
  client.setInsecure();
  client.setHandshakeTimeout(15);
  client.setTimeout(HTTPS_TIMEOUT_MS);

  if (client.connect(FIRESTORE_HOST, 443)) return true;

  delay(250);

  if (WiFi.status() != WL_CONNECTED) {
    if (!ensureWifi()) return false;
  }

  client.stop();
  return client.connect(FIRESTORE_HOST, 443);
}

int fetchCurrentOwnerUid(String& ownerUid) {
  ownerUid = "";

  for (uint8_t attempt = 1; attempt <= 2; attempt++) {
    WiFiClientSecure client;

    if (!openFirestoreTls(client)) {
      Serial.printf("Owner lookup TLS connection failed (%u/2).\n", attempt);
      delay(300UL * attempt);
      continue;
    }

    client.print("GET ");
    client.print(DEVICE_ASSIGNMENT_PATH);
    client.println(" HTTP/1.1");
    client.print("Host: ");
    client.println(FIRESTORE_HOST);
    client.println("Accept: application/json");
    client.println("User-Agent: SoilSense-ESP32");
    client.println("Connection: close");
    client.println();

    HttpsResponse response = readHttpsResponse(client);
    client.stop();

    if (response.status == 200) {
      ownerUid = firestoreStringField(response.body, "currentOwnerUid");
      if (!ownerUid.isEmpty()) cachedOwnerUid = ownerUid;
      return 200;
    }

    if (response.status == 404) {
      cachedOwnerUid = "";
      return 404;
    }

    Serial.printf("Owner lookup HTTP/TLS status: %d (%u/2).\n", response.status, attempt);
    delay(300UL * attempt);
  }

  return -1;
}

String buildReadingBody(const SoilReading& reading, const String& ownerUid) {
  String body;
  body.reserve(900);
  body = "{\"fields\":{";
  body += "\"hardwareFingerprint\":{\"stringValue\":\"" + hardwareFingerprint() + "\"},";
  body += "\"ownerUid\":{\"stringValue\":\"" + ownerUid + "\"},";
  body += "\"nitrogen\":{\"doubleValue\":" + String(reading.nitrogen, 2) + "},";
  body += "\"phosphorus\":{\"doubleValue\":" + String(reading.phosphorus, 2) + "},";
  body += "\"potassium\":{\"doubleValue\":" + String(reading.potassium, 2) + "},";
  body += "\"ph\":{\"doubleValue\":" + String(reading.ph, 2) + "},";
  body += "\"moisture\":{\"doubleValue\":" + String(reading.moisture, 2) + "},";
  body += "\"soilTemperature\":{\"doubleValue\":" + String(reading.temperature, 2) + "},";
  body += "\"electricalConductivity\":{\"integerValue\":\"" + String(reading.electricalConductivity) + "\"},";
  body += "\"source\":{\"stringValue\":\"esp32_https\"},";
  body += "\"authenticationMode\":{\"stringValue\":\"open_firestore_assigned_owner\"},";
  body += "\"firmwareVersion\":{\"stringValue\":\"" + String(FIRMWARE_VERSION) + "\"},";
  body += "\"rssi\":{\"integerValue\":\"" + String(WiFi.RSSI()) + "\"},";
  body += "\"timestamp\":{\"timestampValue\":\"" + firestoreTimestamp() + "\"}";
  body += "}}";
  return body;
}

int postFirestoreRaw(const String& body) {
  WiFiClientSecure client;

  Serial.printf("Firestore TLS: Wi-Fi RSSI %d dBm, free heap %u bytes.\n", WiFi.RSSI(), ESP.getFreeHeap());
  Serial.println("Connecting directly to Firestore HTTPS...");

  if (!openFirestoreTls(client)) {
    Serial.println("ERROR: Could not connect to firestore.googleapis.com:443.");
    return -1;
  }

  client.print("POST ");
  client.print(FIRESTORE_PATH);
  client.println(" HTTP/1.1");
  client.print("Host: ");
  client.println(FIRESTORE_HOST);
  client.println("Content-Type: application/json");
  client.println("Accept: application/json");
  client.println("User-Agent: SoilSense-ESP32");
  client.println("Connection: close");
  client.print("Content-Length: ");
  client.println(body.length());
  client.println();
  client.print(body);

  HttpsResponse response = readHttpsResponse(client);
  client.stop();

  if (response.status < 0) {
    Serial.println("ERROR: Firestore HTTPS did not return a valid HTTP response.");
    return response.status;
  }

  Serial.printf("Firestore response: HTTP %d\n", response.status);

  if (response.status != 200 && !response.body.isEmpty()) {
    Serial.println(response.body);
  }

  return response.status;
}

bool sendReading(const SoilReading& reading) {
  if (!ensureWifi()) {
    Serial.println("Upload cancelled: Wi-Fi is unavailable.");
    return false;
  }

  if (!ensureClock()) {
    Serial.println("Upload cancelled: internet time could not synchronize.");
    return false;
  }

  String ownerUid = cachedOwnerUid;

  if (ownerUid.isEmpty()) {
    Serial.println("Checking the current SoilSense owner...");
    const int assignmentStatus = fetchCurrentOwnerUid(ownerUid);

    if (assignmentStatus == 404 || (assignmentStatus == 200 && ownerUid.isEmpty())) {
      Serial.println("No current owner is assigned. Ask the SoilSense admin to set an Owner before scanning.");
      return false;
    }

    if (assignmentStatus != 200) {
      Serial.println("Could not read the current owner assignment after retrying.");
      return false;
    }
  } else {
    Serial.println("Using cached current owner. Firestore rules will verify it before accepting the scan.");
  }

  String body = buildReadingBody(reading, ownerUid);

  for (uint8_t attempt = 1; attempt <= HTTPS_RETRY_COUNT; attempt++) {
    Serial.printf("Firestore upload attempt %u/%u\n", attempt, HTTPS_RETRY_COUNT);
    const int status = postFirestoreRaw(body);

    if (status == 200) {
      cachedOwnerUid = ownerUid;
      return true;
    }

    if (status == 403) {
      Serial.println("Owner assignment may have changed. Refreshing owner before retrying...");
      cachedOwnerUid = "";
      String refreshedOwnerUid;
      const int refreshedStatus = fetchCurrentOwnerUid(refreshedOwnerUid);

      if (refreshedStatus == 200 && !refreshedOwnerUid.isEmpty()) {
        ownerUid = refreshedOwnerUid;
        cachedOwnerUid = refreshedOwnerUid;
        body = buildReadingBody(reading, ownerUid);
        continue;
      }

      if (refreshedStatus == 200 || refreshedStatus == 404) {
        Serial.println("The device currently has no assigned Owner. Reading was not uploaded.");
        return false;
      }

      Serial.println("Could not refresh the Owner after Firestore denied the upload.");
      return false;
    }

    if (attempt < HTTPS_RETRY_COUNT) {
      delay(500UL * attempt);

      if (WiFi.status() != WL_CONNECTED) {
        ensureWifi();
      }
    }
  }

  return false;
}

void addScanSample(const SoilReading& reading) {
  scanTotals.moisture += reading.moisture;
  scanTotals.temperature += reading.temperature;
  scanTotals.electricalConductivity += reading.electricalConductivity;
  scanTotals.ph += reading.ph;
  scanTotals.nitrogen += reading.nitrogen;
  scanTotals.phosphorus += reading.phosphorus;
  scanTotals.potassium += reading.potassium;
  scanTotals.samples++;
}

void collectScanSample() {
  const SoilReading reading = readAllSensors();
  lastSampleFinishedAt = millis();

  if (!reading.valid) {
    Serial.println("Invalid sensor response; trying again during this scan...");
    return;
  }

  addScanSample(reading);
  Serial.printf(
    "Sample %u: Moisture %.1f%% | pH %.1f | N %.1f | P %.1f | K %.1f\n",
    static_cast<unsigned int>(scanTotals.samples),
    reading.moisture,
    reading.ph,
    reading.nitrogen,
    reading.phosphorus,
    reading.potassium
  );
}

SoilReading calculateAverageReading() {
  SoilReading average{};

  if (scanTotals.samples == 0) {
    average.valid = false;
    return average;
  }

  const double count = scanTotals.samples;
  average.moisture = static_cast<float>(scanTotals.moisture / count);
  average.temperature = static_cast<float>(scanTotals.temperature / count);
  average.electricalConductivity = static_cast<uint16_t>(scanTotals.electricalConductivity / scanTotals.samples);
  average.ph = static_cast<float>(scanTotals.ph / count);
  average.nitrogen = static_cast<float>(scanTotals.nitrogen / count);
  average.phosphorus = static_cast<float>(scanTotals.phosphorus / count);
  average.potassium = static_cast<float>(scanTotals.potassium / count);
  average.valid = true;
  return average;
}

void startScan() {
  if (scanning || provisioningActive || scanSolidIndicatorActive) return;

  // Give immediate physical feedback before any Wi-Fi/Firestore work. The
  // yellow LED stays solid during preparation, then begins blinking only after
  // the mobile app has been told that scanning=true.
  const unsigned long prepareStartedAt = millis();
  scanSolidIndicatorActive = true;
  scanIndicatorActive = false;
  greenLedUntil = 0;

  refreshScanDuration();

  // STOP may be pressed while the duration lookup is in progress. Do not start
  // a scan in that case.
  if (stopPressRequested) {
    stopPressRequested = false;
    scanSolidIndicatorActive = false;
    signalSuccess(1000);
    Serial.println("SCAN START CANCELLED BEFORE SAMPLING. Nothing was uploaded.");
    return;
  }

  scanTotals = ScanAccumulator{};
  scanning = true;
  lastSampleFinishedAt = 0;

  const bool statusSynced = sendDeviceStatus(false);

  if (stopPressRequested) {
    stopPressRequested = false;
    cancelScan();
    return;
  }

  // Keep the solid yellow acknowledgement visible for at least 1.5 seconds.
  // The indicator task continues to run while this function waits.
  while (millis() - prepareStartedAt < YELLOW_START_SOLID_MS) {
    if (stopPressRequested) {
      stopPressRequested = false;
      cancelScan();
      return;
    }
    delay(10);
  }

  scanStartedAt = millis();
  scanSolidIndicatorActive = false;
  scanIndicatorActive = true;

  Serial.println();
  Serial.println("==================================");
  Serial.println("SCAN STARTED");
  Serial.printf("Keep the sensor still for up to %lu seconds.\n", activeScanDurationMs / 1000UL);
  Serial.println("Press the separate STOP button anytime to cancel without uploading.");
  if (!statusSynced) {
    Serial.println("Mobile scan-state sync is retrying in the background.");
  }
  Serial.println("==================================");

  collectScanSample();
}

void cancelScan() {
  if (!scanning) return;

  // Stop sensor collection immediately, discard partial data, and use a solid
  // yellow light while the cancelled state is synchronized. Green is shown
  // only after the app has had time to receive scanning=false.
  scanning = false;
  scanIndicatorActive = false;
  scanSolidIndicatorActive = true;
  yellowActivityUntil = 0;
  scanTotals = ScanAccumulator{};
  lastSampleFinishedAt = 0;

  Serial.println();
  Serial.println("SCAN CANCELLED BY STOP BUTTON");
  Serial.println("Partial samples were discarded. Nothing was uploaded to Firestore.");

  const bool statusSynced = sendDeviceStatus(false);
  scanSolidIndicatorActive = false;
  delay(APP_STATE_SETTLE_MS);
  signalSuccess(1400);
  lastDeviceStatusAttemptAt = millis();

  if (!statusSynced) {
    Serial.println("Cancellation saved locally; mobile state will correct on the next heartbeat.");
  }
}

void finishScan() {
  // Keep the app in scanning state while the final average is validated and
  // uploaded. Yellow changes from blinking to solid to indicate finalizing.
  scanIndicatorActive = false;
  scanSolidIndicatorActive = true;
  yellowActivityUntil = 0;
  Serial.println();
  Serial.printf("SCAN COMPLETED AFTER %lu SECONDS\n", activeScanDurationMs / 1000UL);

  const SoilReading average = calculateAverageReading();

  if (!average.valid) {
    Serial.println("No valid sensor reading was received. Nothing was uploaded.");
    scanning = false;
    sendDeviceStatus(false);
    scanSolidIndicatorActive = false;
    delay(APP_STATE_SETTLE_MS);
    signalError();
    lastDeviceStatusAttemptAt = millis();
    return;
  }

  Serial.printf(
    "Average: Moisture %.1f%% | Temp %.1f C | EC %u | pH %.1f | N %.1f | P %.1f | K %.1f\n",
    average.moisture,
    average.temperature,
    static_cast<unsigned int>(average.electricalConductivity),
    average.ph,
    average.nitrogen,
    average.phosphorus,
    average.potassium
  );

  const bool uploadSucceeded = sendReading(average);
  if (uploadSucceeded) {
    Serial.println("SUCCESS: Soil reading uploaded to Firestore.");
  } else {
    Serial.println("ERROR: Firestore upload failed.");
  }

  // Only clear the app's loading state after the reading upload attempt has
  // finished. This prevents green success from appearing while the mobile app
  // still believes a scan is active.
  scanning = false;
  const bool statusSynced = sendDeviceStatus(false);
  scanSolidIndicatorActive = false;
  delay(APP_STATE_SETTLE_MS);

  if (uploadSucceeded) {
    signalSuccess();
  } else {
    signalError();
  }

  if (!statusSynced) {
    Serial.println("Final mobile scan-state sync will retry on the next heartbeat.");
  }

  lastDeviceStatusAttemptAt = millis();
  Serial.println("Press START for another scan.");
}

void serviceScan() {
  if (!scanning) return;

  const unsigned long now = millis();
  const unsigned long elapsed = now - scanStartedAt;

  if (elapsed >= activeScanDurationMs) {
    finishScan();
    return;
  }

  const unsigned long remaining = activeScanDurationMs - elapsed;
  if (remaining > SENSOR_TIMEOUT_MS && now - lastSampleFinishedAt >= SAMPLE_INTERVAL_MS) collectScanSample();
}


void setup() {
  Serial.begin(115200);
  pinMode(SCAN_BUTTON_PIN, INPUT_PULLUP);
  pinMode(STOP_BUTTON_PIN, INPUT_PULLUP);
  pinMode(BLUE_LED_PIN, OUTPUT);
  pinMode(YELLOW_LED_PIN, OUTPUT);
  pinMode(GREEN_LED_PIN, OUTPUT);
  pinMode(RED_LED_PIN, OUTPUT);
  digitalWrite(BLUE_LED_PIN, LOW);
  digitalWrite(YELLOW_LED_PIN, LOW);
  digitalWrite(GREEN_LED_PIN, LOW);
  digitalWrite(RED_LED_PIN, HIGH);

  xTaskCreatePinnedToCore(
    indicatorButtonTask,
    "soil-ui",
    4096,
    nullptr,
    2,
    &indicatorButtonTaskHandle,
    1
  );

  Serial2.begin(RS485_BAUD_RATE, SERIAL_8N1, RS485_RX_PIN, RS485_TX_PIN);

  if (!RS485_AUTO_DIRECTION) {
    pinMode(RS485_DE_RE_PIN, OUTPUT);
    digitalWrite(RS485_DE_RE_PIN, LOW);
  }

  wifiStorage.begin("soil-wifi", false);
  savedWifiSsid = wifiStorage.getString("ssid", "");
  savedWifiPassword = wifiStorage.getString("password", "");

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);

  Serial.println();
  Serial.println("SoilSense direct Firestore mode started.");
  Serial.print("Device ID: ");
  Serial.println(hardwareFingerprint());

  if (savedWifiSsid.isEmpty()) {
    // First-time setup: there is nothing to reconnect to, so open Wi-Fi setup
    // automatically and turn the blue LED ON.
    startWifiProvisioning();
  } else if (!ensureWifi()) {
    // Hybrid behavior: a saved network that is temporarily unavailable does
    // NOT force setup mode. Keep the blue LED OFF, remain offline, and retry
    // the saved network in the background. The user stays in control and can
    // hold START for 3 seconds if they intentionally want to change Wi-Fi.
    lastWifiReconnectAttemptAt = millis();
    Serial.println("Saved Wi-Fi is currently unavailable.");
    Serial.println("SoilSense will keep retrying it automatically with the blue LED OFF.");
    Serial.println("Hold START for 3 seconds only if you want to configure a different Wi-Fi.");
  } else {
    lastDeviceStatusAttemptAt = 0;
    refreshScanDuration();
    Serial.println("Saved Wi-Fi is ready. Press START to scan.");
  }

  Serial.println("START button (GPIO 27): press to begin the configured scan.");
  Serial.println("STOP button (GPIO 14): press to cancel a scan; partial data is discarded.");
  Serial.println("Hold START 3 seconds: manually enter/change Wi-Fi setup when needed.");
  Serial.println("Hold STOP 3 seconds while blue LED is ON: cancel Wi-Fi setup and restore previous Wi-Fi.");
}

void loop() {
  serviceButtonEvents();
  serviceScan();
  serviceWifiProvisioning();
  serviceWifiReconnect();
  serviceDeviceStatus();
  delay(5);
}
