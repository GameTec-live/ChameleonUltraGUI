#ifndef RECOVERY_CANCEL_H
#define RECOVERY_CANCEL_H

// Shared by the UI thread and native recovery workers. Defined in recovery.c.
int recovery_is_cancelled(void);

#endif
