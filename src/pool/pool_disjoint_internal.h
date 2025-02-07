/*
 * Copyright (C) 2025 Intel Corporation
 *
 * Under the Apache License v2.0 with LLVM Exceptions. See LICENSE.TXT.
 * SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
*/

#ifndef UMF_POOL_DISJOINT_INTERNAL_H
#define UMF_POOL_DISJOINT_INTERNAL_H 1

#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include <umf/memory_pool.h>
#include <umf/memory_pool_ops.h>
#include <umf/memory_provider.h>
#include <umf/pools/pool_disjoint.h>

#include "critnib/critnib.h"
#include "uthash/utlist.h"

#include "base_alloc_global.h"
#include "provider/provider_tracking.h"
#include "utils_common.h"
#include "utils_concurrency.h"
#include "utils_log.h"
#include "utils_math.h"

typedef struct bucket_t bucket_t;
typedef struct slab_t slab_t;
typedef struct slab_list_item_t slab_list_item_t;
typedef struct disjoint_pool_t disjoint_pool_t;

typedef struct bucket_t {
    size_t size;

    // Linked list of slabs which have at least 1 available chunk.
    // We always count available slabs as an optimization.
    slab_list_item_t *available_slabs;
    size_t available_slabs_num;

    // Linked list of slabs with 0 available chunks
    slab_list_item_t *unavailable_slabs;

    // Protects the bucket and all the corresponding slabs
    utils_mutex_t bucket_lock;

    // Reference to the allocator context, used to access memory allocation
    // routines, slab map and etc.
    disjoint_pool_t *pool;

    umf_disjoint_pool_shared_limits_handle_t shared_limits;

    // For buckets used in chunked mode, a counter of slabs in the pool.
    // For allocations that use an entire slab each, the entries in the
    // "available" list are entries in the pool. Each slab is available for a
    // new allocation. The size of the available list is the size of the pool.
    //
    // For allocations that use slabs in chunked mode, slabs will be in the
    // "available" list if any one or more of their chunks are free. The entire
    // slab is not necessarily free, just some chunks in the slab are free. To
    // implement pooling, we will allow one slab in the "available" list to be
    // entirely empty, and treat this slab as "in the pool".
    // When a slab becomes entirely free, we must decide whether to return it
    // to the provider or keep it allocated. We keep a counter of entirely
    // empty slabs within the "available" list to speed up the process of
    // checking if a slab in this bucket is already pooled.
    size_t chunked_slabs_in_pool;

    // Statistics
    size_t alloc_count;
    size_t alloc_pool_count;
    size_t free_count;
    size_t curr_slabs_in_use;
    size_t curr_slabs_in_pool;
    size_t max_slabs_in_pool;
    size_t max_slabs_in_use;
} bucket_t;

// Represents the allocated memory block of size 'slab_min_size'
// Internally, it splits the memory block into chunks. The number of
// chunks depends on the size of a Bucket which created the Slab.
// Note: Bucket's methods are responsible for thread safety of Slab access,
// so no locking happens here.
typedef struct slab_t {
    // Pointer to the allocated memory of slab_min_size bytes
    void *mem_ptr;
    size_t slab_size;

    // Represents the current state of each chunk: if the bit is set, the
    // chunk is allocated; otherwise, the chunk is free for allocation
    bool *chunks;
    size_t num_chunks_total;

    // Total number of allocated chunks at the moment.
    size_t num_chunks_allocated;

    // The bucket which the slab belongs to
    bucket_t *bucket;

    // Hints where to start search for free chunk in a slab
    size_t first_free_chunk_idx;

    // Store iterator to the corresponding node in avail/unavail list
    // to achieve O(1) removal
    slab_list_item_t *iter;
} slab_t;

typedef struct slab_list_item_t {
    slab_t *val;
    struct slab_list_item_t *prev, *next;
} slab_list_item_t;

typedef struct umf_disjoint_pool_shared_limits_t {
    size_t max_size;
    size_t total_size; // requires atomic access
} umf_disjoint_pool_shared_limits_t;

typedef struct umf_disjoint_pool_params_t {
    // Minimum allocation size that will be requested from the memory provider.
    size_t slab_min_size;

    // Allocations up to this limit will be subject to chunking/pooling
    size_t max_poolable_size;

    // When pooling, each bucket will hold a max of 'capacity' unfreed slabs
    size_t capacity;

    // Holds the minimum bucket size valid for allocation of a memory type.
    // This value must be a power of 2.
    size_t min_bucket_size;

    // Holds size of the pool managed by the allocator.
    size_t cur_pool_size;

    // Whether to print pool usage statistics
    int pool_trace;

    // Memory limits that can be shared between multiple pool instances,
    // i.e. if multiple pools use the same shared_limits sum of those pools'
    // sizes cannot exceed max_size.
    umf_disjoint_pool_shared_limits_handle_t shared_limits;

    // Name used in traces
    char *name;
} umf_disjoint_pool_params_t;

typedef struct disjoint_pool_t {
    // Keep the list of known slabs to quickly find required one during the
    // free()
    critnib *known_slabs; // (void *, slab_t *)

    // Handle to the memory provider
    umf_memory_provider_handle_t provider;

    // Array of bucket_t*
    bucket_t **buckets;
    size_t buckets_num;

    // Configuration for this instance
    umf_disjoint_pool_params_t params;

    umf_disjoint_pool_shared_limits_handle_t default_shared_limits;

    // Used in algorithm for finding buckets
    size_t min_bucket_size_exp;

    // Coarse-grain allocation min alignment
    size_t provider_min_page_size;
} disjoint_pool_t;

#endif // UMF_POOL_DISJOINT_INTERNAL_H
