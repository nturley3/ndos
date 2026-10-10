// nDOS image-mount bridge. Shell state and consumption belong to the DOS worker.
#ifndef DOSPAD_IMAGE_MOUNT_H
#define DOSPAD_IMAGE_MOUNT_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool dospad_image_mount_available(void);
void dospad_image_mount_set_prompt_empty(bool empty);
// Supplies Return only at an empty shell prompt, with no buffered BIOS key.
bool dospad_image_mount_take(void);
void dospad_image_mount_done(void);

#ifdef __OBJC__
void dospad_image_mount_request(const char *command, void (^completion)(bool));
#endif

#ifdef __cplusplus
}
#endif

#endif
