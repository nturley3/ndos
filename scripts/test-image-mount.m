// Host regression tests for the production bridge; no simulator is needed.
#import <Foundation/Foundation.h>
#include <assert.h>
#include "dospad_image_mount.h"

char dospad_command_buffer[1024];

static dispatch_semaphore_t resultSignal;
static bool lastAccepted;
static unsigned completions;

static void recordResult(bool accepted)
{
    dispatch_assert_queue(dispatch_get_main_queue());
    lastAccepted = accepted;
    completions++;
    dispatch_semaphore_signal(resultSignal);
}

static void expectResult(bool accepted)
{
    assert(dispatch_semaphore_wait(resultSignal,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    assert(lastAccepted == accepted);
}

static void requestMount(void)
{
    dospad_image_mount_request("imgmount d \"test.iso\" -t iso -fs iso\n", ^(bool accepted) {
        recordResult(accepted);
    });
}

static void runTests(void)
{
    resultSignal = dispatch_semaphore_create(0);

    // Games and partially typed commands are unavailable; nothing reaches DOS.
    assert(!dospad_image_mount_available());
    requestMount();
    expectResult(false);
    assert(!dospad_image_mount_take());
    assert(!dospad_command_buffer[0]);

    // A request is consumed once, and reports success only after execution.
    dospad_image_mount_set_prompt_empty(true);
    assert(dospad_image_mount_available());
    requestMount();
    assert(!dospad_image_mount_available());
    assert(dospad_image_mount_take());
    assert(strstr(dospad_command_buffer, "test.iso"));
    assert(!dospad_image_mount_take());
    assert(dispatch_semaphore_wait(resultSignal, DISPATCH_TIME_NOW) != 0);
    requestMount();
    expectResult(false);
    assert(strstr(dospad_command_buffer, "test.iso"));
    dospad_command_buffer[0] = 0;
    dospad_image_mount_done();
    expectResult(true);
    dospad_image_mount_done();
    assert(dispatch_semaphore_wait(resultSignal, DISPATCH_TIME_NOW) != 0);

    // Input arriving between UI submission and worker consumption cancels the
    // request without injecting Enter or touching the user/command buffer.
    dospad_image_mount_set_prompt_empty(true);
    requestMount();
    dospad_image_mount_set_prompt_empty(false);
    expectResult(false);
    assert(!dospad_image_mount_take());
    assert(!dospad_command_buffer[0]);

    // Do not overwrite a command submitted by an existing, unrelated UI flow.
    dospad_image_mount_set_prompt_empty(true);
    requestMount();
    strcpy(dospad_command_buffer, "existing command");
    assert(!dospad_image_mount_take());
    expectResult(false);
    assert(strcmp(dospad_command_buffer, "existing command") == 0);
    dospad_command_buffer[0] = 0;

    // Reject malformed/oversized requests, including multi-byte UTF-8 paths.
    dospad_image_mount_set_prompt_empty(true);
    NSString *longCommand = [@"é" stringByPaddingToLength:600 withString:@"é" startingAtIndex:0];
    dospad_image_mount_request(longCommand.UTF8String, ^(bool accepted) { recordResult(accepted); });
    expectResult(false);
    dospad_image_mount_request("", ^(bool accepted) { recordResult(accepted); });
    expectResult(false);
    assert(!dospad_command_buffer[0]);

    // Concurrent submissions admit exactly one request; all others complete
    // with unavailable instead of replacing it or opening another command.
    unsigned before = completions;
    dispatch_apply(32, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t index) {
        requestMount();
    });
    for (int i = 0; i < 31; i++) expectResult(false);
    assert(dospad_image_mount_take());
    dospad_command_buffer[0] = 0;
    dospad_image_mount_done();
    expectResult(true);
    assert(completions == before + 32);
    dospad_image_mount_set_prompt_empty(true);
    assert(dospad_image_mount_available());
    puts("Image mount bridge tests passed");
}

int main(void)
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        @autoreleasepool {
            runTests();
            exit(0);
        }
    });
    dispatch_main();
}
