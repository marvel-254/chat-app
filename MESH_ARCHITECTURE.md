# BRO Mesh Architecture — "Offline-First Opportunistic Mesh"

**Target:** Path B — always-on background mesh where devices relay for each other, expanding range.

**Reality check upfront:** iOS *cannot* do background BLE relay. This architecture is **Android-primary** with iOS as "foreground-only participant" (AWDL for iOS↔iOS, BLE when app open). If that's unacceptable, stop here and do Path A.

---

## 1. Topology & Transport Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                          │
│  MeshChatService (text, file metadata, sync contracts)       │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                    MESH ROUTING LAYER                         │
│  Epidemic/Gossip Routing + TTL + Bloom Filters               │
│  - Store-and-forward queue per peer                          │
│  - Encryption envelope (sender→recipient, relay-blind)       │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                    TRANSPORT ABSTRACTION                      │
│  Transport interface: connect(), send(), listen(), close()   │
└─────────────────────────────────────────────────────────────┘
┌──────────────┬──────────────┬──────────────┬────────────────┐
│  BLE (GATT)  │  Nearby      │  Wi-Fi Direct│  AWDL (iOS)    │
│  flutter_blue│  Connections │  (Android)   │  (iOS↔iOS)     │
│  _plus       │  (Android)   │              │                │
└──────────────┴──────────────┴──────────────┴────────────────┘
```

### Transport Selection Policy (Android)

| Scenario | Transport |
|---|---|
| Peer discovered, both Android, Play Services available | **Nearby Connections** (P2P_STAR or P2P_CLUSTER) — handles multi-band, higher throughput, built-in relay |
| Peer discovered, no Play Services / China devices | **BLE GATT** via `flutter_blue_plus` — manual relay |
| iOS peer detected (app in foreground) | **BLE GATT** (iOS peripheral/central) |
| iOS peer, both iOS, app foreground | **AWDL** via `multipeer_connectivity` (future) |

> **Nearby Connections is the workhorse.** It gives you: automatic BLE discovery → Wi-Fi Direct upgrade → 10–50 Mbps, multi-hop cluster support, background operation via Foreground Service.

---

## 2. Message Envelope (Wire Format)

```protobuf
// mesh_envelope.proto (compile to Dart with protoc)
syntax = "proto3";
package bro.mesh;

message MeshEnvelope {
  string message_id = 1;           // UUID v4
  uint32 version = 2;              // protocol version
  string sender_pubkey = 3;        // Ed25519 public key (base64)
  string recipient_pubkey = 4;     // Ed25519 public key (base64) — encrypted for this key
  uint32 ttl = 5;                  // hop limit (default 7)
  uint64 timestamp = 6;            // unix ms
  PayloadType payload_type = 7;
  bytes encrypted_payload = 8;     // see Payload types
  bytes signature = 9;             // Ed25519 over all above fields
  repeated string seen_by = 10;    // peer IDs this has visited (loop detection)
  BloomFilter bloom = 11;          // optional: recipients this peer knows about
}

enum PayloadType {
  TEXT = 0;
  FILE_META = 1;      // filename, size, hash, chunk_count
  FILE_CHUNK = 2;     // chunk_index, total_chunks, data
  ACK = 3;            // message_id being acked
  SYNC_REQUEST = 4;   // "I have messages for X, do you?"
  SYNC_OFFER = 5;     // "I have these message_ids for you"
  TOPOLOGY = 6;       // peer advertising: "I know routes to [pubkeys]"
}

message FileMeta {
  string file_id = 1;
  string filename = 2;
  uint64 size = 3;
  string sha256 = 4;
  uint32 chunk_count = 5;
  string mime_type = 6;
}

message FileChunk {
  string file_id = 1;
  uint32 chunk_index = 2;
  bytes data = 3;          // max ~16 KB (BLE MTU friendly)
}
```

**Encryption:** Sender encrypts `encrypted_payload` with **X25519 + ChaCha20-Poly1305** (libsodium / `dart_nacl`):
- Ephemeral sender keypair per message
- Recipient's long-term Curve25519 public key (from profile)
- Relays see only: `sender_pubkey`, `recipient_pubkey`, `ttl`, `payload_type`, `timestamp` — **cannot read content**

---

## 3. Identity & Key Management

```
┌────────────────────────────────────────┐
│  User Identity (per install)           │
│  - Ed25519 signing keypair (identity)  │
│  - X25519 encryption keypair (boxes)   │
│  - Stored in Flutter Secure Storage    │
│  - Public keys synced to Supabase      │
│    `profiles.mesh_public_keys` JSONB   │
└────────────────────────────────────────┘
```

- On first mesh enable: generate keypair, upload public keys to Supabase.
- Profile lookup: `SELECT mesh_public_keys FROM profiles WHERE username = ?`
- **Key rotation:** re-key on device change; old keys retained for in-flight messages (2-week grace).

---

## 4. Routing: Epidemic/Gossip with Bloom Filters

**Why not AODV/OLSR?** Those need route discovery round-trips. In opportunistic mesh, contacts are fleeting — you forward *now* or lose the chance.

### Algorithm (per peer)

```dart
// Pseudocode — actual in lib/services/mesh/router.dart

class MeshRouter {
  // In-memory: Map<peerId, PeerState>
  // PeerState: { pubkey, lastSeen, knownRecipients: BloomFilter, queue: List<MeshEnvelope> }

  void onPeerDiscovered(Peer peer) {
    // Exchange bloom filters: "who do you have messages for?"
    send(SYNC_REQUEST, bloom: myBloomFilter);
  }

  void onEnvelopeReceived(MeshEnvelope env, String fromPeer) {
    if (env.seenBy.contains(myPeerId)) return; // loop
    if (env.ttl == 0) return;

    env.seenBy.add(myPeerId);
    env.ttl--;

    if (env.recipientPubkey == myPubkey) {
      // For me — decrypt, deliver to UI
      deliverLocally(env);
      sendAck(env.messageId);
      return;
    }

    // Not for me — do I know a better path?
    PeerState? nextHop = chooseNextHop(env.recipientPubkey, exclude: fromPeer);
    if (nextHop != null) {
      forward(env, to: nextHop);
    } else {
      // Store for opportunistic forward
      queueForRecipient(env.recipientPubkey, env);
    }
  }

  PeerState? chooseNextHop(String recipientPubkey, {String? exclude}) {
    // Score peers by: (knowsRecipient? 10 : 0) + recency + queueDepth
    // Prefer peer whose bloom filter contains recipient
  }
}
```

**Bloom filter:** 256-bit, 3 hash functions — fits in one BLE packet. Each peer advertises "I have recent contact with these pubkeys."

**TTL default: 7 hops.** At ~30 m/hop indoors, 7 hops ≈ 200 m chain — realistic for dense crowds.

---

## 5. Store-and-Forward Queue (Persistence)

```dart
// lib/services/mesh/queue.dart — uses drift (SQLite) or Hive

class MeshQueue {
  // Tables:
  // messages: id, envelope_bytes, recipient_pubkey, status, created_at, attempts
  // peers: pubkey, last_seen, bloom_filter_bytes, transport_hint

  // Status: PENDING → SENDING → ACKED / EXPIRED
  // Retry: exponential backoff (1s, 2s, 4s... max 5 min), max 20 attempts
  // TTL expiry: drop after 7 days (configurable)

  // Per-recipient FIFO — fairness so one chatty contact doesn't starve others
}
```

**Disk budget:** cap at 500 MB (user-configurable). Oldest-expired-first eviction.

---

## 6. File Transfer Design (Chunked + Resumable)

```
Sender                                    Relay(s)                              Recipient
  │                                         │                                      │
  ├─ FILE_META (file_id, size, hash, chunks) ──────────────────────────────────► │
  │                                         │                                      │
  ├─ FILE_CHUNK 0 ──────────────────────────► │ (stores, forwards when sees recip) │
  ├─ FILE_CHUNK 1 ──────────────────────────► │                                     │
  ...                                       ...                                     │
  ├─ FILE_CHUNK N ──────────────────────────► │                                     │
  │                                         │                                      │
  ◄──────────────────────────── ACK per chunk (or bitmap) ────────────────────────┤
  │                                         │                                      │
  └─ On all ACKs: mark FILE_META delivered ──► │                                     │
```

- **Chunk size:** 16 KB (fits BLE MTU 512 with overhead, ~32 packets).
- **Parallelism:** 1 chunk in flight per peer at a time (BLE is half-duplex-ish).
- **Resume:** Recipient persists received chunk bitmap; on reconnect, requests missing chunks via `SYNC_REQUEST` with bitmap.
- **Large files:** >50 MB → warn user "this will take hours over mesh; prefer online sync."

---

## 7. Sync Bridge: Mesh ↔ Supabase

This is the **killer integration** — mesh messages become part of normal conversations.

```dart
// lib/services/mesh/sync_bridge.dart

class MeshSyncBridge {
  final SupabaseService supabase;
  final MeshRouter router;

  // Called when connectivity_plus reports online
  Future<void> syncOnOnline() async {
    // 1. Pull undelivered mesh messages from local queue
    final pending = await queue.getUndeliveredForMyPubkey();

    // 2. For each, try Supabase direct send (fast path)
    for (env in pending) {
      final convId = await resolveConversationId(env.senderPubkey, env.recipientPubkey);
      if (convId != null) {
        await supabase.sendMessage(convId, decrypt(env));
        await queue.markAcked(env.messageId);
      }
    }

    // 3. Pull new Supabase messages since last mesh sync timestamp
    //    → re-encrypt for mesh peers who were offline
    //    → inject into local queue for opportunistic delivery
  }

  // Background: periodic (15 min) or on connectivity change
}
```

**Message deduplication:** `message_id` (UUID) is the universal key. Supabase `messages` table gets `mesh_message_id` column (nullable, unique). On receive, `UPSERT ON CONFLICT (mesh_message_id) DO NOTHING`.

---

## 8. Android Implementation Stack

| Layer | Package | Notes |
|---|---|---|
| Nearby Connections | `nearby_connections` (Flutter) | Google Play Services required. Handles BLE→WiFi Direct upgrade, clustering, background. |
| BLE Fallback | `flutter_blue_plus` | Manual GATT. Use when Nearby unavailable. |
| Foreground Service | `flutter_foreground_task` or custom Kotlin | Required for background scanning/advertising. Notification: "BRO Mesh active — tapping opens app." |
| Crypto | `dart_nacl` or `pointycastle` | X25519 + ChaCha20-Poly1305 + Ed25519. |
| Local DB | `drift` (SQLite) | Queue, peer cache, bloom filters. |
| Protobuf | `protobuf` (dart) | Wire format. |
| WorkManager | `workmanager` | Periodic sync-on-online, queue maintenance. |

**AndroidManifest additions:**

```xml
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

---

## 9. iOS Reality Layer (Honest)

| Capability | Status |
|---|---|
| BLE Central (scan) in background | ❌ Killed ~3 min after lock |
| BLE Peripheral (advertise) in background | ❌ Killed ~3 min after lock |
| AWDL (MultipeerConnectivity) | ✅ Works foreground, *some* background via `UIBackgroundModes: bluetooth-central` but unreliable |
| Nearby Connections | ❌ Android only |
| Wi-Fi Direct | ❌ Not exposed to apps |

**iOS MVP scope:**
- Mesh **only works when app is open** (foreground).
- Uses `flutter_blue_plus` for BLE to Android peers.
- Uses `multipeer_connectivity` (new plugin needed) for iOS↔iOS high-speed.
- Background: **no relay, no receive.** Push notification via APNs/FCM says "Open BRO to receive mesh messages."

**Do not promise background mesh on iOS.** Put it in the UI: "Mesh works best on Android. On iPhone, keep the app open to relay/receive."

---

## 10. Milestones & Scope

### M1 — Foundation (2–3 weeks)
- [ ] Protobuf envelope + crypto (libsodium bindings)
- [ ] Identity keypair gen + Supabase sync
- [ ] Drift schema: queue, peers, bloom
- [ ] Nearby Connections transport (Android)
- [ ] Basic router: discover → direct 1:1 text → ack

### M2 — Relay & Persistence (2 weeks)
- [ ] Epidemic routing with bloom filters
- [ ] Store-and-forward queue with retry/TTL
- [ ] Foreground Service + background scanning (Android)
- [ ] File meta + chunk transfer (text-first, files work but slow)

### M3 — Sync Bridge (1–2 weeks)
- [ ] Mesh → Supabase deduplication
- [ ] Supabase → Mesh re-encryption for offline peers
- [ ] Connectivity monitor integration

### M4 — iOS Foreground + Polish (2 weeks)
- [ ] BLE transport parity (flutter_blue_plus)
- [ ] MultipeerConnectivity plugin (or skip, BLE-only)
- [ ] UI: mesh status indicator, "offline mode" badge, peer list

### M5 — Hardening (ongoing)
- [ ] Battery profiling (target <3%/hr idle scanning)
- [ ] Stress test: 20 devices, 100 m chain
- [ ] Key rotation UX
- [ ] Encrypted local DB (sqlcipher)

---

## 11. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| iOS background kill | Certain | High (no iOS relay) | Document honestly; make Android mesh shine |
| Nearby Connections flakiness (Play Services version) | High | Medium | BLE fallback; graceful degradation |
| BLE throughput too low for files | Certain | Medium | Chunking + resumable; set expectations |
| Battery drain complaints | High | High | Foreground service with "pause mesh" toggle; adaptive scan duty cycle |
| Regulatory (BLE beacon restrictions EU/China) | Low | Medium | Runtime permission checks; disable in restricted regions |
| Spam/abuse via mesh | Medium | High | Rate-limit per pubkey; blocklist sync from Supabase |

---

## 12. File Tree (Proposed)

```
lib/
  services/
    mesh/
      mesh_service.dart           # Main entrypoint, lifecycle
      transport/
        transport.dart            # Interface
        nearby_transport.dart     # Nearby Connections
        ble_transport.dart        # flutter_blue_plus
        awdl_transport.dart       # iOS Multipeer (future)
      router.dart                 # Epidemic routing + bloom
      queue.dart                  # Drift persistence
      crypto.dart                 # Box/Seal/Open, signing
      sync_bridge.dart            # Supabase ↔ Mesh
      models/
        envelope.pb.dart          # Generated protobuf
        peer.dart
      android/
        mesh_foreground_service.kt
      ios/
        (placeholder)
```

---

## 13. Next Step

**Do you want me to:**

1. **Scaffold the mesh module** — create the directory structure, `pubspec.yaml` additions, protobuf schema, Drift tables, and crypto primitives? (I can do this in one pass.)
2. **Prototype M1 Nearby Connections transport** — working Android 1:1 text demo with discovery + send + ack?
3. **Write the Supabase migration** for `profiles.mesh_public_keys` and `messages.mesh_message_id`?

Say the word and I'll start generating code.