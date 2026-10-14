// Startup-only finite exact-resource discovery. No Lua on worker.
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include "lua.h"
#include "lauxlib.h"
#define TAG "tenbucks.regular_discovery"
typedef AXUIElementRef (*Make)(CFDataRef);
typedef AXError (*GetWindow)(AXUIElementRef, CGWindowID *);
typedef struct { pid_t pid; CGWindowID id; AXUIElementRef root; } Target;
typedef struct { pid_t pid; uint64_t attempts, errors, last; double elapsed, overshoot; } Stats;
typedef struct {
    pthread_mutex_t lock;
    atomic_bool cancelled;
    atomic_uint refs;
    bool drained;
    Target *targets; Stats *stats;
    unsigned count, groups;
    double started, elapsed, overshoot;
    Make make; GetWindow get;
} Job;
static dispatch_queue_t queue;
static void *pin;
static dispatch_once_t once;
int luaopen_regular_discovery(lua_State *L);
static double now(void) {
    mach_timebase_info_data_t t; mach_timebase_info(&t);
    return (double)mach_absolute_time() * t.numer / t.denom / 1e9;
}
static void clear(Job *j) {
    for (unsigned i=0; i<j->count; i++) if (j->targets[i].root) {
        CFRelease(j->targets[i].root); j->targets[i].root=NULL;
    }
}
static void release(Job *j) {
    if (atomic_fetch_sub(&j->refs,1)==1) {
        clear(j); free(j->targets); free(j->stats);
        pthread_mutex_destroy(&j->lock); free(j);
    }
}
static bool allowed(Job *j, double deadline) {
    return !atomic_load(&j->cancelled) && now()<deadline;
}
static void run(Job *j) {
    j->started=now(); double totalDeadline=j->started+.5;
    for (unsigned g=0; g<j->groups && !atomic_load(&j->cancelled); g++) {
        Stats *s=&j->stats[g]; double start=now(), deadline=fmin(start+.1,totalDeadline);
        unsigned remaining=0;
        for (unsigned i=0; i<j->count; i++) if (j->targets[i].pid==s->pid) remaining++;
        for (uint64_t element=1; element<=4096 && remaining && allowed(j,deadline); element++) {
            unsigned char bytes[20]={0}; uint32_t magic=0x636f636f;
            memcpy(bytes,&s->pid,4); memcpy(bytes+8,&magic,4); memcpy(bytes+12,&element,8);
            CFDataRef data=CFDataCreate(NULL,bytes,20);
            AXUIElementRef ax=data ? j->make(data) : NULL;
            if (data) CFRelease(data);
            s->attempts++; s->last=element;
            if (!ax) { s->errors++; continue; }
            CGWindowID wid=0; pid_t pid=0; CFTypeRef role=NULL;
            AXError error=kAXErrorFailure;
            if (allowed(j,deadline)) error=AXUIElementSetMessagingTimeout(ax,.001);
            if (error==kAXErrorSuccess && allowed(j,deadline)) error=j->get(ax,&wid);
            Target *target=NULL;
            if (error==kAXErrorSuccess) for (unsigned i=0; i<j->count; i++) {
                Target *t=&j->targets[i];
                if (t->pid==s->pid && t->id==wid && !t->root) { target=t; break; }
            }
            if (target) {
                if (allowed(j,deadline)) error=AXUIElementGetPid(ax,&pid);
                if (error==kAXErrorSuccess && allowed(j,deadline))
                    error=AXUIElementCopyAttributeValue(ax,kAXRoleAttribute,&role);
                if (error==kAXErrorSuccess && pid==s->pid && role &&
                    CFGetTypeID(role)==CFStringGetTypeID() && CFEqual(role,kAXWindowRole)) {
                    target->root=ax; CFRetain(ax); remaining--;
                } else s->errors++;
            } else if (error!=kAXErrorSuccess) s->errors++;
            if (role) CFRelease(role); CFRelease(ax);
        }
        s->elapsed=now()-start; s->overshoot=fmax(0,now()-deadline);
        if (now()>=totalDeadline) break;
    }
    j->elapsed=now()-j->started; j->overshoot=fmax(0,j->elapsed-.5);
    pthread_mutex_lock(&j->lock);
    if (atomic_load(&j->cancelled)) clear(j);
    j->drained=true;
    pthread_mutex_unlock(&j->lock); release(j);
}
static Job *check(lua_State *L) {
    Job *j=*(Job **)luaL_checkudata(L,1,TAG);
    luaL_argcheck(L,j!=NULL,1,"job collected"); return j;
}
static void cancelJob(Job *j) {
    atomic_store(&j->cancelled,true);
    pthread_mutex_lock(&j->lock); if (j->drained) clear(j); pthread_mutex_unlock(&j->lock);
}
static int cancel(lua_State *L) { cancelJob(check(L)); return 0; }
static int gc(lua_State *L) {
    Job **p=luaL_checkudata(L,1,TAG);
    if (*p) { cancelJob(*p); release(*p); *p=NULL; } return 0;
}
static int status(lua_State *L) {
    Job *j=check(L); pthread_mutex_lock(&j->lock); bool drained=j->drained; pthread_mutex_unlock(&j->lock);
    lua_newtable(L); lua_pushboolean(L,drained); lua_setfield(L,-2,"drained");
    lua_pushboolean(L,atomic_load(&j->cancelled)); lua_setfield(L,-2,"cancelled");
    return 1;
}
#define NUMBER(name,value) do { lua_pushnumber(L,(value)); lua_setfield(L,-2,(name)); } while(0)
static int poll(lua_State *L) {
    Job *j=check(L); pthread_mutex_lock(&j->lock);
    bool done=j->drained, cancelled=atomic_load(&j->cancelled);
    pthread_mutex_unlock(&j->lock);
    lua_newtable(L); lua_pushboolean(L,done); lua_setfield(L,-2,"done");
    lua_pushboolean(L,cancelled); lua_setfield(L,-2,"cancelled");
    if (!done || cancelled) return 1; // immutable terminal data, main-thread cancellation only
    NUMBER("startedAt",j->started); NUMBER("elapsedMs",j->elapsed*1000); NUMBER("overshootMs",j->overshoot*1000);
    lua_newtable(L);
    for (unsigned g=0; g<j->groups; g++) {
        Stats *s=&j->stats[g]; lua_newtable(L);
        NUMBER("pid",s->pid); NUMBER("attempts",s->attempts); NUMBER("errors",s->errors);
        NUMBER("lastElement",s->last); NUMBER("elapsedMs",s->elapsed*1000); NUMBER("overshootMs",s->overshoot*1000);
        lua_rawseti(L,-2,g+1);
    }
    lua_setfield(L,-2,"stats"); lua_newtable(L);
    for (unsigned i=0; i<j->count; i++) {
        Target *t=&j->targets[i]; lua_newtable(L); NUMBER("pid",t->pid); NUMBER("windowId",t->id);
        lua_pushboolean(L,t->root==NULL); lua_setfield(L,-2,"unresolved");
        if (t->root) {
            AXUIElementRef *p=lua_newuserdata(L,sizeof(*p)); *p=t->root; CFRetain(*p);
            luaL_getmetatable(L,"hs.axuielement"); lua_setmetatable(L,-2); lua_setfield(L,-2,"ax");
        }
        lua_rawseti(L,-2,i+1);
    }
    lua_setfield(L,-2,"results"); return 1;
}
static int inventory(lua_State *L) {
    CFArrayRef rows=CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID);
    if (!rows) return luaL_error(L,"native inventory unavailable");
    lua_newtable(L); unsigned count=0;
    for (CFIndex i=0; i<CFArrayGetCount(rows); i++) {
        CFDictionaryRef row=CFArrayGetValueAtIndex(rows,i);
        int64_t id=0,pid=0,layer=0;
        CFNumberRef n=CFDictionaryGetValue(row,kCGWindowNumber);
        CFNumberRef p=CFDictionaryGetValue(row,kCGWindowOwnerPID);
        CFNumberRef l=CFDictionaryGetValue(row,kCGWindowLayer);
        if (!n || !p || !l) continue;
        CFNumberGetValue(n,kCFNumberSInt64Type,&id); CFNumberGetValue(p,kCFNumberSInt64Type,&pid);
        CFNumberGetValue(l,kCFNumberSInt64Type,&layer);
        lua_newtable(L); NUMBER("windowId",id); NUMBER("pid",pid); NUMBER("layer",layer);
        lua_rawseti(L,-2,++count);
    }
    CFRelease(rows); return 1;
}
static int create(lua_State *L) {
    luaL_checktype(L,1,LUA_TTABLE); unsigned count=(unsigned)lua_rawlen(L,1);
    luaL_argcheck(L,count>0,1,"nonempty {pid, windowId} targets required");
    luaL_getmetatable(L,"hs.axuielement"); bool bridge=lua_istable(L,-1); lua_pop(L,1);
    if (!bridge) return luaL_error(L,"load hs.axuielement first");
    Make make=dlsym(RTLD_DEFAULT,"_AXUIElementCreateWithRemoteToken");
    GetWindow get=dlsym(RTLD_DEFAULT,"_AXUIElementGetWindow");
    if (!make || !get) return luaL_error(L,"private symbols unavailable");
    // Validate all primitive inputs before allocating native ownership.
    for (unsigned i=1; i<=count; i++) {
        lua_rawgeti(L,1,i); luaL_checktype(L,-1,LUA_TTABLE);
        lua_getfield(L,-1,"pid"); lua_Integer pid=luaL_checkinteger(L,-1); lua_pop(L,1);
        lua_getfield(L,-1,"windowId"); lua_Integer id=luaL_checkinteger(L,-1); lua_pop(L,2);
        luaL_argcheck(L,pid>0 && pid<=INT32_MAX && id>0 && id<=UINT32_MAX,1,"invalid PID/window ID");
    }
    Job **ud=lua_newuserdata(L,sizeof(*ud)); *ud=NULL; luaL_getmetatable(L,TAG); lua_setmetatable(L,-2);
    Job *j=calloc(1,sizeof(*j)); if (!j) return luaL_error(L,"allocation failed");
    j->targets=calloc(count,sizeof(Target)); j->stats=calloc(count,sizeof(Stats));
    if (!j->targets || !j->stats) { free(j->targets); free(j->stats); free(j); return luaL_error(L,"allocation failed"); }
    pthread_mutex_init(&j->lock,NULL); atomic_init(&j->refs,2); atomic_init(&j->cancelled,false);
    j->make=make; j->get=get; j->count=count;
    for (unsigned i=0; i<count; i++) {
        lua_rawgeti(L,1,i+1); lua_getfield(L,-1,"pid"); pid_t pid=(pid_t)lua_tointeger(L,-1); lua_pop(L,1);
        lua_getfield(L,-1,"windowId"); CGWindowID id=(CGWindowID)lua_tointeger(L,-1); lua_pop(L,2);
        j->targets[i]=(Target){pid,id,NULL};
        unsigned g=0; while (g<j->groups && j->stats[g].pid!=pid) g++;
        if (g==j->groups) j->stats[j->groups++].pid=pid;
        for (unsigned k=0; k<i; k++) if (j->targets[k].pid==pid && j->targets[k].id==id) {
            atomic_store(&j->refs,1); release(j); return luaL_error(L,"duplicate target");
        }
    }
    *ud=j; dispatch_async(queue,^{ run(j); }); return 1;
}
int luaopen_regular_discovery(lua_State *L) {
    dispatch_once(&once,^{
        Dl_info info;
        if (dladdr((void *)&luaopen_regular_discovery,&info) && info.dli_fname)
            pin=dlopen(info.dli_fname,RTLD_NOW|RTLD_LOCAL|RTLD_NODELETE);
        if (pin) queue=dispatch_queue_create("tenbucks.regular-discovery",DISPATCH_QUEUE_SERIAL);
    });
    if (!pin || !queue) return luaL_error(L,"image pin/queue failed");
    luaL_newmetatable(L,TAG); lua_pushcfunction(L,gc); lua_setfield(L,-2,"__gc"); lua_newtable(L);
    const luaL_Reg methods[]={{"poll",poll},{"cancel",cancel},{"status",status},{NULL,NULL}};
    luaL_setfuncs(L,methods,0); lua_setfield(L,-2,"__index"); lua_pop(L,1);
    lua_newtable(L); lua_pushcfunction(L,create); lua_setfield(L,-2,"create");
    lua_pushcfunction(L,inventory); lua_setfield(L,-2,"inventory"); return 1;
}
