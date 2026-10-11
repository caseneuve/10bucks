// Source-only POC: exact retained AX resource, no Lua/native query on worker main.
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dispatch/dispatch.h>
#import <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <dlfcn.h>

// Process-lifetime public loader pin: worker/cancel blocks can outlive Lua reload.
static dispatch_once_t pinOnce;
static void *imagePin;
#include "lua.h"
#include "lauxlib.h"
int luaopen_ax_validity(lua_State *L);

#define TAG "tenbucks.ax_validity"
typedef struct { lua_Integer token; AXError error; double at, cost; } Row;
typedef struct {
    pthread_mutex_t lock;
    atomic_uint refs;
    bool active, inflight, drained;
    uint64_t generation;
    AXUIElementRef target;
    lua_Integer token;
    dispatch_queue_t queue;
    dispatch_source_t timer;
    Row rows[64]; unsigned head, count, dropped;
} Probe;

static double seconds(void) {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    return (double)mach_absolute_time() * info.numer / info.denom / 1e9;
}
static void releaseProbe(Probe *p) {
    if (atomic_fetch_sub(&p->refs, 1) == 1) {
        pthread_mutex_destroy(&p->lock);
        free(p);
    }
}
static Probe *check(lua_State *L) {
    Probe *p = *(Probe **)luaL_checkudata(L, 1, TAG);
    luaL_argcheck(L, p != NULL, 1, "probe collected");
    return p;
}
static void tick(Probe *p) {
    pthread_mutex_lock(&p->lock);
    AXUIElementRef target = p->active ? p->target : NULL;
    uint64_t generation = p->generation;
    lua_Integer token = p->token;
    if (target) { CFRetain(target); p->inflight = true; }
    pthread_mutex_unlock(&p->lock);
    if (!target) return;
    double at = seconds();
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue(target, kAXRoleAttribute, &value);
    double cost = seconds() - at;
    if (value) CFRelease(value); // never export the native role value
    CFRelease(target);
    pthread_mutex_lock(&p->lock);
    p->inflight = false;
    if (p->active && p->generation == generation) {
        if (p->count == 64) { p->head = (p->head + 1) % 64; p->count--; p->dropped++; }
        p->rows[(p->head + p->count++) % 64] = (Row){token, error, at, cost};
    }
    pthread_mutex_unlock(&p->lock);
}
static void stopProbe(Probe *p) {
    pthread_mutex_lock(&p->lock);
    AXUIElementRef target = p->target;
    dispatch_source_t timer = p->timer;
    p->active = false; p->generation++; p->target = NULL; p->timer = NULL;
    p->count = 0;
    pthread_mutex_unlock(&p->lock);
    if (target) CFRelease(target);
    if (timer) {
        // Cancel handler on serial queue releases worker ownership AFTER any
        // in-flight AX query. No synchronous join/barrier on the Lua thread.
        dispatch_source_cancel(timer);
        dispatch_release(timer);
    }
}
static int create(lua_State *L) {
    Probe **ud = lua_newuserdata(L, sizeof(*ud)); *ud = NULL;
    luaL_getmetatable(L, TAG); lua_setmetatable(L, -2);
    Probe *p = calloc(1, sizeof(*p));
    if (!p) return luaL_error(L, "probe allocation failed");
    pthread_mutex_init(&p->lock, NULL); atomic_init(&p->refs, 1); p->active = true;
    p->queue = dispatch_queue_create("tenbucks.ax-probe", DISPATCH_QUEUE_SERIAL);
    p->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, p->queue);
    if (!p->timer) {
        dispatch_release(p->queue); releaseProbe(p);
        return luaL_error(L, "probe timer allocation failed");
    }
    atomic_fetch_add(&p->refs, 1); // worker lifetime, independent of Lua userdata
    dispatch_source_set_event_handler(p->timer, ^{ tick(p); });
    dispatch_source_set_cancel_handler(p->timer, ^{
        pthread_mutex_lock(&p->lock); p->drained = true; pthread_mutex_unlock(&p->lock);
        dispatch_release(p->queue); releaseProbe(p);
    });
    dispatch_source_set_timer(p->timer, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                             100 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    *ud = p;
    dispatch_resume(p->timer); // serial source coalesces ticks; no query overlap
    return 1;
}
static int set(lua_State *L) {
    Probe *p = check(L);
    lua_Integer token = luaL_checkinteger(L, 3);
    AXUIElementRef target = NULL;
    if (!lua_isnil(L, 2)) {
        void *ud = luaL_checkudata(L, 2, "hs.axuielement");
        luaL_argcheck(L, lua_rawlen(L, 2) == sizeof(AXUIElementRef), 2, "AX userdata size mismatch");
        target = *(AXUIElementRef *)ud;
        luaL_argcheck(L, target && CFGetTypeID(target) == AXUIElementGetTypeID(), 2, "AX type mismatch");
        CFRetain(target);
    }
    pthread_mutex_lock(&p->lock);
    if (!p->active) {
        pthread_mutex_unlock(&p->lock);
        if (target) CFRelease(target);
        return luaL_error(L, "probe stopped");
    }
    AXUIElementRef old = p->target;
    p->target = target; p->token = token; p->generation++; p->count = 0;
    pthread_mutex_unlock(&p->lock);
    if (old) CFRelease(old);
    return 0;
}
static int poll(lua_State *L) {
    Probe *p = check(L); Row rows[64]; unsigned count, dropped;
    pthread_mutex_lock(&p->lock);
    count = p->count; dropped = p->dropped; p->dropped = 0;
    for (unsigned i = 0; i < count; i++) rows[i] = p->rows[(p->head + i) % 64];
    p->count = 0; p->head = 0;
    pthread_mutex_unlock(&p->lock);
    lua_createtable(L, count, 0);
    for (unsigned i = 0; i < count; i++) {
        Row r = rows[i]; lua_createtable(L, 0, 5);
        lua_pushinteger(L, r.token); lua_setfield(L, -2, "token");
        lua_pushinteger(L, r.error); lua_setfield(L, -2, "error");
        lua_pushstring(L, r.error == kAXErrorSuccess ? "valid" :
                       r.error == kAXErrorInvalidUIElement ? "invalid" : "unknown");
        lua_setfield(L, -2, "status");
        lua_pushnumber(L, r.at); lua_setfield(L, -2, "sampled_at");
        lua_pushnumber(L, r.cost); lua_setfield(L, -2, "query_seconds");
        lua_rawseti(L, -2, i + 1);
    }
    lua_pushinteger(L, dropped); return 2;
}
static int status(lua_State *L) {
    Probe *p = check(L);
    pthread_mutex_lock(&p->lock);
    bool active = p->active, inflight = p->inflight, drained = p->drained;
    unsigned queued = p->count, dropped = p->dropped;
    pthread_mutex_unlock(&p->lock);
    lua_createtable(L, 0, 5);
    lua_pushboolean(L, active); lua_setfield(L, -2, "active");
    lua_pushboolean(L, inflight); lua_setfield(L, -2, "inflight");
    lua_pushboolean(L, drained); lua_setfield(L, -2, "drained");
    lua_pushinteger(L, queued); lua_setfield(L, -2, "queuedResults");
    lua_pushinteger(L, dropped); lua_setfield(L, -2, "dropped");
    return 1;
}
static int stop(lua_State *L) {
    double at = seconds(); stopProbe(check(L));
    lua_pushnumber(L, seconds() - at); return 1;
}
static int gc(lua_State *L) {
    Probe **ud = luaL_checkudata(L, 1, TAG);
    if (*ud) { stopProbe(*ud); releaseProbe(*ud); *ud = NULL; }
    return 0;
}
__attribute__((visibility("default"))) int luaopen_ax_validity(lua_State *L) {
    dispatch_once(&pinOnce, ^{
        Dl_info info;
        if (dladdr((const void *)&luaopen_ax_validity, &info) && info.dli_fname)
            imagePin = dlopen(info.dli_fname, RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE);
    });
    if (!imagePin) return luaL_error(L, "probe image pin failed");
    luaL_newmetatable(L, TAG);
    lua_pushcfunction(L, gc); lua_setfield(L, -2, "__gc");
    lua_newtable(L);
    const luaL_Reg methods[] = {{"set", set}, {"poll", poll}, {"stop", stop}, {"status", status}, {NULL, NULL}};
    luaL_setfuncs(L, methods, 0); lua_setfield(L, -2, "__index"); lua_pop(L, 1);
    lua_newtable(L); lua_pushcfunction(L, create); lua_setfield(L, -2, "create"); return 1;
}
