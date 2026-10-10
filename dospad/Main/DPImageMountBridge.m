// Image mounts never send an SDL Return from the UI thread. The DOS worker
// consumes the request at an empty prompt and supplies Return directly to CON.
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <string.h>
#include "dospad_image_mount.h"

extern char dospad_command_buffer[];

static pthread_mutex_t mountLock = PTHREAD_MUTEX_INITIALIZER;
static bool promptEmpty;
static char pendingCommand[1024];
static void (^pendingCompletion)(bool);
static void (^activeCompletion)(bool);

static void completeMount(void (^completion)(bool), bool accepted)
{
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(accepted); });
    }
}

bool dospad_image_mount_available(void)
{
    pthread_mutex_lock(&mountLock);
    bool available = promptEmpty && !pendingCompletion && !activeCompletion;
    pthread_mutex_unlock(&mountLock);
    return available;
}

void dospad_image_mount_request(const char *command, void (^completion)(bool))
{
    NSCParameterAssert(completion);
    size_t length = command ? strlen(command) : 0;
    pthread_mutex_lock(&mountLock);
    bool accepted = length > 0 && length < sizeof(pendingCommand)
        && promptEmpty && !pendingCompletion && !activeCompletion;
    if (accepted) {
        memcpy(pendingCommand, command, length + 1);
        pendingCompletion = [completion copy];
    }
    pthread_mutex_unlock(&mountLock);
    if (!accepted) completeMount(completion, false);
}

void dospad_image_mount_set_prompt_empty(bool empty)
{
    pthread_mutex_lock(&mountLock);
    promptEmpty = empty;
    void (^rejected)(bool) = nil;
    if (!empty && pendingCompletion) {
        rejected = pendingCompletion;
        pendingCompletion = nil;
        pendingCommand[0] = 0;
    }
    pthread_mutex_unlock(&mountLock);
    completeMount(rejected, false);
}

bool dospad_image_mount_take(void)
{
    pthread_mutex_lock(&mountLock);
    bool accepted = promptEmpty && pendingCompletion && !dospad_command_buffer[0];
    void (^rejected)(bool) = nil;
    if (accepted) {
        strcpy(dospad_command_buffer, pendingCommand);
        activeCompletion = pendingCompletion;
        pendingCompletion = nil;
        pendingCommand[0] = 0;
        promptEmpty = false;
    } else if (pendingCompletion) {
        rejected = pendingCompletion;
        pendingCompletion = nil;
        pendingCommand[0] = 0;
    }
    pthread_mutex_unlock(&mountLock);
    completeMount(rejected, false);
    return accepted;
}

void dospad_image_mount_done(void)
{
    pthread_mutex_lock(&mountLock);
    void (^completed)(bool) = activeCompletion;
    activeCompletion = nil;
    pthread_mutex_unlock(&mountLock);
    completeMount(completed, true);
}
