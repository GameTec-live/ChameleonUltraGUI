# HF inspection tools

Connect a Chameleon Ultra with firmware advertising the relevant command, then
open **Tools**.

- **HF tag selection** uses scan-keep (2016), lists every card record returned,
  and lets you select a record to inspect UID, ATQA, SAK and ATS. The RF field is
  released after scanning. Firmware may return only one tag; selecting a result
  does not target later reader commands.
- **Active authentication trace** uses command 2017 with a block (0–255), Key A
  or B, a six-byte hexadecimal key, and a polling timeout (1–30000 ms). Present
  only the intended card because firmware selects independently. Status 0 means
  authentication succeeded; other statuses and partial frames remain visible.
  Anticollision frames are reconstructed by firmware; authentication frames are
  captured live.

Active traces use the existing summary, frame, nonce, recovery and raw views.
Save exports a Proxmark-compatible `.trace` file that can be loaded again in the
HF trace tools. Timing and parity in active exports are synthesized, not captured
RF measurements. Recovery requires sufficient nonce exchanges; a single active
capture does not guarantee a recoverable key.
