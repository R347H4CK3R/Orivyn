/* Independent upstream framing smoke test. This is NOT the Swift transport test. */
#include "c_nio_llhttp.h"
#include <stdio.h>
#include <stdlib.h>
static size_t body_bytes = 0;
static unsigned long body_sum = 0;
static int complete = 0;
static int body(llhttp_t *parser, const char *data, size_t length) {
    (void)parser;
    body_bytes += length;
    for (size_t i = 0; i < length; i++) body_sum += (unsigned char)data[i];
    return 0;
}
static int message_complete(llhttp_t *parser) { (void)parser; complete++; return 0; }
int main(int argc, char **argv) {
    llhttp_t parser;
    llhttp_settings_t settings;
    c_nio_llhttp_settings_init(&settings);
    settings.on_body = body;
    settings.on_message_complete = message_complete;
    c_nio_llhttp_init(&parser, HTTP_RESPONSE, &settings);
    char buffer[8192];
    size_t chunk = argc > 1 ? (size_t)atoi(argv[1]) : sizeof(buffer);
    if (chunk == 0 || chunk > sizeof(buffer)) return 2;
    llhttp_errno_t status = HPE_OK;
    size_t count;
    while ((count = fread(buffer, 1, chunk, stdin)) > 0) {
        status = c_nio_llhttp_execute(&parser, buffer, count);
        if (status != HPE_OK) break;
    }
    if (status == HPE_OK) status = c_nio_llhttp_finish(&parser);
    printf("{\"status\":%d,\"body_bytes\":%zu,\"body_sum\":%lu,\"complete\":%d}\n", status, body_bytes, body_sum, complete);
    return 0;
}
