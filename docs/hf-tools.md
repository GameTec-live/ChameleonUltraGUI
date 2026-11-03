# Active authentication traces

Connect a Chameleon Ultra with firmware advertising command 2017, then open
**Tools → Active authentication trace**.

Enter a block (0–255), Key A or B, a six-byte hexadecimal key, and a polling
timeout (1–30000 ms). Present only the intended card because firmware selects
independently. Status 0 means authentication succeeded; other statuses and partial
frames remain visible. Anticollision frames are reconstructed by firmware;
authentication frames are captured live.

Active traces use the existing summary, frame, nonce, recovery and raw views.
Save exports a Proxmark-compatible `.trace` file that can be loaded again in the
HF trace tools. Timing and parity in active exports are synthesized, not captured
RF measurements. Recovery requires sufficient nonce exchanges; a single active
capture does not guarantee a recoverable key.
