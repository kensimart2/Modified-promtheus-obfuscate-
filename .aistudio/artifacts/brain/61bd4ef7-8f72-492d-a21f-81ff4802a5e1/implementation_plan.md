# Peningkatan Proteksi Ketahanan Layer 1 (Luraph Polymorphic Metatable Stager)

Rencana peningkatan arsitektur Layer 1 (Stager Luraph) untuk memblokir celah hooking, inspeksi AST statis, dan dynamic payload dumping terhadap Layer 2, dirancang tahan terhadap automated reversing/skid agent tanpa melampaui batas ukuran ~100KB-125KB.

> [!IMPORTANT]
> **Keputusan Kunci Arsitektur**:
> - **Penyamaran Variabel & State**: Menghilangkan sepenuhnya variabel statis terbuka (seperti `_K = number`) menjadi dynamic runtime state derivation melalui rantai metamethod polymorphism (`__index`, `__call`, `__concat`).
> - **Anti-Dump & Silent Poisoning**: Menghindari penghentian instan `return nil` yang memberi indikasi deteksi kepada analis. Jika terdeteksi hook/debugger, kunci dekripsi bermutasi secara hening (*silent drift*) sehingga payload yang terdekripsi menjadi byte sampah tanpa mengekspos isi Layer 2.
> - **Anti-Hooking Multilapis**: Validasi integritas closure dan global runtime (`rawget`, `getfenv`, `load`/`loadstring`, `string.dump`, coroutine state check) secara natural tanpa pola heuristik yang tertebak.
> - **Ukuran Output**: Mempertahankan kompresi LZSS + Base85 berdensitas tinggi dengan kamus substitusi frekuensi tinggi agar output tetap berada pada kisaran optimal 100KB–120KB.

---

## 1. Overview & Konsep Arsitektur

Layer 1 bertindak sebagai gerbang terluar (*outer envelope*) yang mengenkapsulasi Layer 2. Saat ini, deobfuscator atau analis mengincar titik temu saat stager memanggil fungsi kompilasi (`loadstring` / `load`) atau mengekstrak nilai kunci `_K` secara langsung dari AST.

Peningkatan ini merombak Layer 1 menjadi mesin metamethod berantai di mana:
1. Tidak ada kunci enkripsi yang tersimpan secara eksplisit. Kunci dihitung dari evaluasi metamethod aritmetika dan permutasi tabel internal.
2. Logika eksekusi tidak berada dalam satu fungsi linier `rH`, melainkan tersebar di dalam dispatch table dengan alias opcode dinamis.
3. Hook interception dilindungi oleh mekanisme silent poison, menjamin bahwa breakpoint ataupun runtime hooking pada `loadstring` hanya akan menangkap instruksi invalid/corrupted.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Stager Entry: setmetatable({}, meta)                 │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                        [Runtime Metamethod Dispatch]
                        (__call, __index, __concat)
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│               Dynamic Environment Integrity & Hook Sensor             │
│   - Closure purity check (string.dump & C-boundary check)             │
│   - Hook trace check (debug hook flags, proxy wrappers)               │
└───────────────────┬────────────────────────────────┬───────────────────┘
                    │ Normal                         │ Tampered / Hooked
                    ▼                                ▼
┌────────────────────────────────────────┐  ┌───────────────────────────┐
│ Dynamic Key Derivation (State Hash)    │  │ Silent Poison Drift       │
│ - Derivasi multi-stage LCG seed        │  │ - Key offset bergeser     │
│ - Unscramble cipher stream             │  │ - Payload menjadi decoy   │
└───────────────────┬────────────────────┘  └─────────────┬─────────────┘
                    │                                     │
                    ▼                                     ▼
┌────────────────────────────────────────┐  ┌───────────────────────────┐
│ LZSS Multi-Level Streaming Decompress  │  │ Corrupted Decode Output   │
└───────────────────┬────────────────────┘  └─────────────┬─────────────┘
                    │                                     │
                    ▼                                     ▼
┌────────────────────────────────────────┐  ┌───────────────────────────┐
│ Virtual Invoker Execution (Layer 2)    │  │ Syntax / Runtime Trap     │
└────────────────────────────────────────┘  └───────────────────────────┘
```

---

## 2. Rincian Peningkatan Teknis

### A. Dynamic Key Derivation via Metatable Dispatch
- **Sebelumnya**: Tabel stager menyimpan `_K = <angka>` yang mudah dibaca analis atau regex parser.
- **Peningkatan**:
  - Kunci dipecah menjadi polinomial dinamis yang dievaluasi saat runtime melalui kombinasi entri tabel dummy dan metamethod `__index` / `__call`.
  - Nilai kunci bergantung pada panjang payload, checksum header, dan akumulasi nilai tabel stager itu sendiri.

### B. Proteksi Anti-Hooking & Anti-Dumping (Silent Poisoning)
- **Sebelumnya**: Stager mendeteksi hook lalu langsung mengeksekusi `if _chk then return nil end`.
- **Peningkatan**:
  - Pemeriksaan dilakukan menggunakan validasi representasi closure (`pcall(string.dump, ...)`) dan pengecekan flag hook native.
  - Jika lingkungan terdeteksi tidak bersih (misalnya `loadstring` di-*override* oleh skid atau automated sandbox), stager **tidak keluar**, melainkan melakukan pergeseran seed LCG (*poison drift*).
  - Proses dekripsi tetap berjalan sampai akhir, namun string yang dikirim ke `loadstring` merupakan byte terdistorsi atau decoy payload, sehingga skid tidak pernah mendapatkan bytecode Layer 2 yang valid.

### C. Polymorphic Metamethod State Machine
- Mengubah fungsi eksekutor linier menjadi alur metamethod bertingkat:
  - Pembacaan kamus frekuensi Base85 dikemas dalam metamethod resolver.
  - Decoding byte dilakukan secara streaming untuk meminimalkan alokasi memori sementara yang mudah di-dump melalui memori scanner.

### D. Kontrol Anggaran Ukuran (Size Budget < 125KB)
- Stager runtime template dioptimalkan dengan penamaan mangled ringkas tanpa deadweight string.
- Kompresor LZSS mempertahankan pencarian match hingga 4095-byte window dan Base85 4-to-5 byte packing untuk menjaga rasio kompresi maksimal pada bytecode Layer 2.

---

## 3. Rencana Pengujian & Validasi

1. **Uji Fungsionalitas**: Memastikan script terobfuscasi tetap berjalan normal 100% pada interpreter Lua 5.1 dan Luau standar.
2. **Uji Batas Ukuran**: Memverifikasi ukuran file hasil obfuscation tetap berada di rentang 100KB–120KB (di bawah batas toleransi 130KB).
3. **Uji Anti-Dump / Interception**: Menguji bahwa lingkungan dengan hooked `loadstring` atau memory scanner hanya menangkap payload terkorupsi tanpa mengekspos isi asli Layer 2.
4. **Verifikasi Build & Suite Test**: Memastikan seluruh test suite unit web worker (`vitest`) berhasil tanpa error.
