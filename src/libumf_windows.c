/*
 *
 * Copyright (C) 2024-2025 Intel Corporation
 *
 * Under the Apache License v2.0 with LLVM Exceptions. See LICENSE.TXT.
 * SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
 *
 */

#include <windows.h>

#include <umf.h>

#if defined(UMF_SHARED_LIBRARY) /* SHARED LIBRARY */

BOOL APIENTRY DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    (void)hinstDLL;    // unused
    (void)lpvReserved; // unused

    if (fdwReason == DLL_PROCESS_ATTACH) {
        (void)umfInit();
    } else if (fdwReason == DLL_PROCESS_DETACH) {
        (void)umfTearDown();
    }
    return TRUE;
}

void libumfInit(void) {
    // do nothing, additional initialization not needed
}

#else /* STATIC LIBRARY */

INIT_ONCE init_once_flag = INIT_ONCE_STATIC_INIT;

static void umfTearDownWrapper(void) { (void)umfTearDown(); }

BOOL CALLBACK initOnceCb(PINIT_ONCE InitOnce, PVOID Parameter,
                         PVOID *lpContext) {
    (void)InitOnce;  // unused
    (void)Parameter; // unused
    (void)lpContext; // unused

    umf_result_t ret = umfInit();
    atexit(umfTearDownWrapper);
    return (ret == UMF_RESULT_SUCCESS) ? TRUE : FALSE;
}

void libumfInit(void) {
    InitOnceExecuteOnce(&init_once_flag, initOnceCb, NULL, NULL);
}

#endif
