# Beyond Bluetooth: Alternative Frequencies for Phone Mesh

**TL;DR:** There are **three** other radios in your phone that can do peer-to-peer without cell/Wi-Fi infrastructure. Only **one** is practical for cross-platform mesh today.

---

## The Radio Inventory (What's Actually in Your Phone)

| Radio | Frequency | Max Range | Throughput | Android API | iOS API | Mesh Viability |
|---|---|---|---|---|---|---|
| **Bluetooth LE** | 2.4 GHz | 30–100 m | 1–2 Mbps | ✅ Full | ✅ Limited | **Baseline** |
| **Wi-Fi Direct** | 2.4/5 GHz | 200–400 m | 250+ Mbps | ✅ Full | ❌ None | Android-only |
| **Wi-Fi Aware (NAN)** | 2.4/5 GHz | 200–500 m | 100+ Mbps | ✅ (API 26+) | ❌ None | **Best Android** |
| **UWB (Ultra-Wideband)** | 6.5/8 GHz | 10–30 m | 27 Mbps | ✅ (API 31+) | ✅ (iOS 13+) | Ranging only |
| **Ultrasound (Near-Ultrasonic)** | 18–20 kHz | 1–3 m | ~100 bps | ✅ AudioRecord | ✅ AVAudioEngine | **Cross-platform** |
| **NFC** | 13.56 MHz | 0.04 m | 424 kbps | ✅ | ✅ | Tap only |
| **5G NR Sidelink / LTE Direct** | Licensed bands | km | Mbps | ❌ Carrier | ❌ Carrier | **Not accessible** |
| **LoRa / Meshtastic** | 868/915 MHz | km | 0.3–50 kbps | ❌ External HW | ❌ External HW | Hardware add-on |

---

## 1. Wi-Fi Aware (Neighbor Awareness Networking) — The Hidden Gem

**What it is:** A Wi-Fi standard (802.11mc/NAN) that lets devices discover and talk **directly** without an AP, using the *same Wi-Fi radio* but in a mesh-friendly mode. Think "Wi-Fi Direct but designed for continuous low-power discovery."

| Property | Value |
|---|---|
| Range | 200–500 m outdoor, 50–100 m indoor (walls hurt less than BLE) |
| Throughput | 50–200 Mbps real-world (TCP over NAN data path) |
| Power | ~2–3× BLE idle, but **100× more data/Joule** |
| Discovery | Continuous, background-capable on Android |
| Identity | MAC randomization + service names (e.g., "bro.mesh") |

### Android Support
- **API 26+ (Android 8.0)** — `WifiAwareManager`, `PublishConfig`, `SubscribeConfig`
- **Background:** Works in `ForegroundService` with `FOREGROUND_SERVICE_DATA_SYNC`
- **Flutter plugin:** `wifi_aware` (community, needs maintenance) or write via Pigeon/Kotlin

### iOS Support
- **None.** Apple exposes **MultipeerConnectivity** (which uses AWDL — Apple's proprietary NAN-like layer) but **only to iOS/macOS devices**. No cross-platform NAN.

### Why this is the Android mesh upgrade
```
BLE:        30 m, 1 Mbps,  100% phones,  background ✅ (Android)
Wi-Fi Aware: 100 m, 100 Mbps, 95% phones (2018+), background ✅ (Android)
```
**100× throughput, 3× range, same radio.** File transfer becomes *fast* (seconds not hours).

### Implementation Sketch
```kotlin
// Android Kotlin — WifiAwareManager callback
val publisher = wifiAwareManager.publish(
    PublishConfig.Builder()
        .setServiceName("bro.mesh")
        .setMatchFilter(byteArrayOf(0x42, 0x52, 0x4F)) // "BRO" magic
        .build(),
    object : DiscoverySessionCallback() {
        override fun onMessageReceived(peerHandle: PeerHandle, message: ByteArray) {
            // Got a mesh envelope from nearby peer
            deliverToFlutter(message)
        }
    }
)
```
Flutter side: `MethodChannel` or `Pigeon` to `WifiAwareTransport` implementing the `Transport` interface from `MESH_ARCHITECTURE.md`.

---

## 2. Near-Ultrasonic (Audio) — The Universal Cross-Platform Fallback

**What it is:** Encode data as 18–20 kHz tones (barely audible to adults, inaudible to most >25). Speaker → Air → Mic. Works on **every smartphone** since 2010.

| Property | Value |
|---|---|
| Range | 1–3 m (line of sight), through thin barriers |
| Throughput | 50–200 bps (with OFDM + FEC) |
| Power | High (speaker + mic always on) |
| Cross-platform | ✅ Android + iOS + Web + Desktop |
| Background | ❌ iOS kills mic access in background |

### Why it matters
- **Only transport that works Android ↔ iOS in background** (if both apps foreground).
- Zero permissions beyond `RECORD_AUDIO` / `MODIFY_AUDIO_SETTINGS`.
- Use case: "Tap phones to exchange keys / bootstrap mesh session / send a 200-byte text."

### Libraries
- **Google Nearby Connections** *already uses this* as one of its discovery mediums (alongside BLE, Wi-Fi Hotspot, Bluetooth Classic).
- **Chirp.io / Sonarax** — commercial SDKs (closed).
- **Open:** `nearby_connections` Flutter plugin exposes it automatically.
- **DIY:** `flutter_sound` + custom OFDM modem (hard, don't).

### In Your Stack
```dart
// Nearby Connections strategy = P2P_CLUSTER
// Automatically uses: BLE + Ultrasonic + Wi-Fi Hotspot + Wi-Fi Direct
// You get ultrasonic "for free" as a bootstrap channel.
```

---

## 3. UWB (Ultra-Wideband) — Precision, Not Throughput

**What it is:** Impulse radio at 6.5/8 GHz. Centimeter-accurate ranging. **Not a data pipe.**

| Use in Mesh | Value |
|---|---|
| "Is peer *actually* nearby?" | ✅ Prevents relay spoofing |
| "Which direction?" | ✅ UI: "Peer 3 m →" |
| Data transfer | ❌ 27 Mbps but only 10 m, high power, no broadcast |

**Verdict:** Add later for **presence verification**, not transport.

---

## 4. Wi-Fi Hotspot (Legacy AP Mode) — The Brute Force Option

One device creates AP (`WifiManager.startLocalOnlyHotspot`), others connect as stations.

| Property | Value |
|---|---|
| Range | 100–200 m |
| Throughput | 50+ Mbps |
| Battery | **Destroyer** (AP mode = full TX power) |
| Cross-platform | ✅ Android → iOS connects as client |
| Background | ❌ iOS won't stay connected in background |

**Used by:** Nearby Connections as `STRATEGY_P2P_STAR` fallback. **Don't implement manually.**

---

## 5. The "Holy Grail" That Doesn't Exist (Yet)

| Dream | Reality |
|---|---|
| 5G NR Sidelink (PC5 interface) | Standardized in 3GPP Rel-16, **modem firmware locked**, carrier-controlled. No app API. |
| LTE Direct / ProSe | Same — carrier enable required, zero deployed networks. |
| LoRa in phone | No phone has a LoRa radio. Meshtastic = external $30 dongle. |
| Satellite (Starlink Direct-to-Cell) | Text-only, carrier partnership, not mesh. |

---

## Practical Transport Hierarchy for BRO Mesh

```
┌─────────────────────────────────────────────────────────────┐
│                  TRANSPORT SELECTION LOGIC                   │
└─────────────────────────────────────────────────────────────┘

onPeerDiscovered(peer):
  if (bothAndroid && hasPlayServices && wifiAwareSupported):
      use WIFI_AWARE (primary) + NEARBY_CONNECTIONS (fallback)
  else if (bothAndroid && hasPlayServices):
      use NEARBY_CONNECTIONS (BLE + Ultrasonic + Hotspot + WiFi Direct)
  else if (androidAndIOS && appForegroundBoth):
      use NEARBY_CONNECTIONS (BLE + Ultrasonic only)
  else if (iOSOnly && appForegroundBoth):
      use MULTIPEER_CONNECTIVITY (AWDL)  // future plugin
  else:
      queue for later / notify "open app to connect"
```

**Code structure:** Each transport implements `MeshTransport` interface. `TransportManager` picks best available at runtime.

---

## What This Means for Your Architecture

| MESH_ARCHITECTURE.md Section | Update |
|---|---|
| **Transport Abstraction** | Add `WifiAwareTransport` (Android), keep `NearbyTransport` as multi-mode |
| **Routing** | Wi-Fi Aware links = "high-capacity edges" — prefer for file chunks |
| **File Transfer** | Chunk over Wi-Fi Aware (100 Mbps) → 10 MB in <2 sec vs 2 hrs on BLE |
| **iOS** | Still foreground-only. Wi-Fi Aware doesn't change this. |
| **Battery** | Wi-Fi Aware idle scan ~2× BLE. Duty-cycle: scan 1s / 5s when screen off. |

---

## Immediate Next Steps

1. **Add `wifi_aware` plugin** (or write thin Pigeon wrapper) — test on two Android 10+ devices.
2. **Keep `nearby_connections`** as the unified API — it already multiplexes BLE + Ultrasonic + Wi-Fi Direct + Hotspot.
3. **Benchmark:** Measure actual throughput/range/power on your test devices.
4. **Defer UWB, LoRa, 5G Sidelink** — not accessible to apps today.

---

## One More Thing: **Thread / Matter / Bluetooth Mesh Profile**

| Standard | Phone Support | Mesh Type |
|---|---|---|
| Bluetooth Mesh (SIG) | ❌ No phone implements the *mesh profile* (only GATT) | Managed flood |
| Thread / Matter | ❌ Requires Thread radio (not in phones) | IPv6 mesh |
| Wi-Fi Mesh (EasyMesh) | ❌ AP coordination, not phone-to-phone | Infrastructure |

**None of these run on smartphones.** They're for lightbulbs and routers.

---

## Summary

| Goal | Transport |
|---|---|
| **Cross-platform, any phone, foreground** | Nearby Connections (BLE + Ultrasonic) |
| **Android background, high throughput, range** | **Wi-Fi Aware (NAN)** — your secret weapon |
| **iOS ↔ iOS foreground, high throughput** | MultipeerConnectivity (AWDL) — future |
| **Bootstrap / key exchange / "tap to connect"** | Ultrasonic (via Nearby) |
| **Background iOS** | **Impossible** — Apple says no |

**Your stack:** Nearby Connections as the unified Android API (it picks Wi-Fi Aware when available), `flutter_blue_plus` for raw BLE fallback, ultrasonic comes free. Wi-Fi Aware is the *only* frequency that meaningfully expands range + speed beyond BLE on Android.

Want me to scaffold the `WifiAwareTransport` alongside the Nearby one?