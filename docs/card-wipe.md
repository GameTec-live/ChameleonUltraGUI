# Wipe card

Open **Tools → Wipe card**, present one card, and choose **Detect card**.
Review its type and UID, enter its current password/key when necessary, confirm
that data will be erased, then choose **Wipe card**. Keep the same card in place
until the operation finishes. Detection never writes to a card.

Supported writable areas:

- **MIFARE Classic Mini/1K/2K/4K:** reuse the existing dictionary checks and key
  recovery, restore both keys to `FFFFFFFFFFFF` and transport access conditions
  (`FF078069`), and zero user blocks. Manufacturer block 0 is preserved.
- **Ultralight, Ultralight EV1, NTAG210/212/213/215/216:** zero user pages and,
  for password-capable cards, disable AUTH0 protection, mirroring and optional
  counter features, restore PWD to `FFFFFFFF` and PACK to `0000`. Reserved
  configuration bytes and permanent configuration locks are preserved. Supply
  the current password for a protected card; passwords are not guessed because
  failed attempts can exhaust the card's authentication limit.
- **Ultralight C:** authenticate with the supplied 16-byte logical 3DES key
  (or the standard `425245414B4D454946594F5543414E21` key), disable protection,
  clear user pages, and restore that standard key.
- **T55xx:** enable the explicit fallback only for a known T55xx tag. The current
  firmware cannot positively identify T55xx silicon or read back raw blocks.
  Supply its current password if enabled. The tool sends open configuration
  `00148040` first (RF/64 Manchester, max block 2, PWD/AOR disabled), then clears
  password block 7 without password mode. Clearing data blocks 1–6 is enabled
  by default and can be turned off. Page 1 and permanent lock bits are preserved.
  The result always says **unverified**, since firmware success only confirms
  command transmission, even if no tag responded.

HF success requires readback of user data and configuration, plus verification
of the restored password/key. Failed areas are reported as incomplete, rather
than claiming a full reset. A stopped wipe can have already changed some data
or credentials. Unknown/ambiguous HF models are rejected without writes; other
families (such as DESFire, ISO15693 and EM4x05) are not supported by this tool.
UID/manufacturer memory, OTP, permanent lock bits and monotonic counters cannot
be erased on ordinary cards. A wipe cannot undo those restrictions. Enabled NTAG
read counters can increment automatically on the first READ after power-on,
including configuration reads during detection or wiping; their exact values
are not guaranteed to remain unchanged.

Configuration references: [NXP Type 2 tag password protection](https://docs.nxp.com/bundle/NTAG213_215_216/page/topics/pwd_auth.html),
[NXP Ultralight C datasheet](https://www.nxp.com.cn/docs/en/data-sheet/MF0ICU2.pdf),
[Microchip ATA5577C datasheet](https://ww1.microchip.com/downloads/aemDocuments/documents/WSG/ProductDocuments/DataSheets/ATA5577C-Read-Write-LF-RFID-IDIC-100-to-150-kHz-Data-Sheet-DS70005357B.pdf).
