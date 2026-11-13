#!/usr/bin/env python3
"""Scene tests by closed-loop simulation: scene_test_pass and a2_scene_test_pass, on any platform, without Factory I/O.

Method.  The program is wrapped as compile_check.py does (fixed configuration, task interval 20 ms; a program that
brings its own configuration keeps it and runs at its own task interval, as in the runtime), the scene-test
parameters of the situation are set as set_params.py does, and the result is compiled by the matiec (iec2c) of
OpenPLC Runtime version 3 at the pinned commit, with the flags and library of the runtime's compilation script.  The
C code is linked with a glue that reproduces the runtime loop (located variables; __CURRENT_TIME advanced by the
task interval after every config_run__, as glueVars.cpp of utils/glue_generator_src does), and driven in closed loop
by models of the Factory I/O scenes.  Every situation of scene_tests_en.md is run once under the nominal scene model
below; scene_test_pass is 1 only if every situation passes.  Nothing of the program is re-implemented.

Nominal scene model (version 1).  Official data, read 2026-11-13 from docs.factoryio.com: tank height 3 m and diameter
2 m, maximum input flow 0.25 m3/s, maximum output flow 0.3543 m3/s, discharge pipe radius 0.125 m, valves and level
meter 0-10 V (manual/parts/stations); roller conveyor default velocity 0.45 m/s (manual/parts/sensors); the driver
multiplies sensor values by Scale and divides actuator values by it (manual/drivers/modbus-server), Scale = 100.
OpenPLC Runtime polls the slave device every 100 ms (default of webserver/openplc.db at the pinned commit); the
simulation exchanges inputs and outputs every 100 ms rounded to a whole number of scans.
Assumptions where the documentation is silent: the outflow is proportional to the discharge-valve opening and to the
square root of the level (Torricelli; with the official pipe radius, sqrt(2 g 3 m) gives 0.377 m3/s at a full tank,
close to the official 0.3543 m3/s); valves follow their command at once; a level switch is on while the level is at
or above its height (LSH 2.4 m, LSHH 2.7 m); buttons are pressed for 0.3 s; sensor B of Scene 2 is 2.0 m downstream
of sensor A, boxes are 0.4 m long, and a box stops when the conveyor stops.  --sensitivity reruns every situation
under alternative assumptions (VARIANTS) and reports how many still pass; these runs do not change the verdict.

Limits.  The scene model is not Factory I/O: its physics, the undocumented parts of the scenes and the Modbus link
are modelled, not reproduced.  Agreement with Factory I/O is to be measured on a validation subset (protocol.md).

Usage:
  python3 scene_sim.py --openplc OPENPLC_V3_DIR --file prog.st --task T2            # one program, all situations
  python3 scene_sim.py --openplc OPENPLC_V3_DIR runs.csv --base ARTIFACTS [--write] [--sensitivity]
  python3 scene_sim.py --openplc OPENPLC_V3_DIR --selftest                          # programs that must fail
"""
import argparse
import csv
import ctypes
import hashlib
import importlib.util
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCENE_MODEL = 'scene model v1 (2026-11-13)'
TS = 0.02          # task interval of the fixed configuration (s); a program's own configuration may set another
POLL = 0.1         # OpenPLC slave-device polling period (s)
A_TANK = math.pi * 1.0 ** 2
H_TANK = 3.0
Q_IN, Q_OUT = 0.25, 0.3543
V_CONV = 0.45
PRESS = 0.3


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


set_params = _load('set_params')
compile_check = _load('compile_check')

GLUE = r'''
#include "iec_std_lib.h"
#include <string.h>
TIME __CURRENT_TIME;
BOOL __DEBUG;
extern unsigned long long common_ticktime__;
#define __LOCATED_VAR(type, name, ...) type __##name;
#include "LOCATED_VARIABLES.h"
#undef __LOCATED_VAR
#define __LOCATED_VAR(type, name, ...) type* name = &__##name;
#include "LOCATED_VARIABLES.h"
#undef __LOCATED_VAR
void config_init__(void);
void config_run__(unsigned long tick);
static unsigned long vc_tick = 0;
struct vc_loc { const char *name; void *ptr; int size; };
#define __LOCATED_VAR(type, name, ...) { #name, (void *)&__##name, (int)sizeof(type) },
static vc_loc vc_locs[] = {
#include "LOCATED_VARIABLES.h"
  { 0, 0, 0 } };
#undef __LOCATED_VAR
static vc_loc *vc_find(const char *n) { for (vc_loc *l = vc_locs; l->name; l++) if (!strcmp(l->name, n)) return l; return 0; }
#define VC_API extern "C" __attribute__((visibility("default")))
VC_API void vc_init(void) { __CURRENT_TIME.tv_sec = 0; __CURRENT_TIME.tv_nsec = 0; vc_tick = 0; config_init__(); }
VC_API void vc_scan(void) {
  config_run__(vc_tick++);
  __CURRENT_TIME.tv_sec  += common_ticktime__ / 1000000000ULL;
  __CURRENT_TIME.tv_nsec += common_ticktime__ % 1000000000ULL;
  if (__CURRENT_TIME.tv_nsec >= 1000000000ULL) { __CURRENT_TIME.tv_nsec -= 1000000000ULL; __CURRENT_TIME.tv_sec += 1; }
}
VC_API int vc_get(const char *n) {
  vc_loc *l = vc_find(n); if (!l) return -99999;
  if (l->size == 1) return *(unsigned char *)l->ptr;
  if (l->size == 2) return *(short *)l->ptr;
  return *(int *)l->ptr;
}
VC_API int vc_set(const char *n, int v) {
  vc_loc *l = vc_find(n); if (!l) return -1;
  if (l->size == 1) *(unsigned char *)l->ptr = (unsigned char)(v != 0);
  else if (l->size == 2) *(short *)l->ptr = (short)v;
  else *(int *)l->ptr = v;
  return 0;
}
VC_API unsigned long long vc_ticktime(void) { return common_ticktime__; }
/* The runtime's TCP client (core/client.cpp) backs library blocks for network access; programs under test cannot
   reach a network here, so these stubs only satisfy the dynamic loader and report failure if ever called. */
int connect_to_tcp_server(uint8_t *ip_address, uint16_t port, int method) { return -1; }
int send_tcp_message(uint8_t *msg, size_t msg_size, int socket_id) { return -1; }
int receive_tcp_message(uint8_t *msg_buffer, size_t buffer_size, int socket_id) { return -1; }
int close_tcp_connection(int socket_id) { return -1; }
'''


def cname(loc):
    """'%IX100.0' -> '__IX100_0', '%QW101' -> '__QW101'."""
    return '__' + loc[1:].replace('.', '_')


class PLC:
    """One compiled program (shared object).  Located variables that the program does not declare are not connected:
    writing them is ignored and reading them gives 0; they are listed in .missing."""

    def __init__(self, st_text, openplc, cache):
        h = hashlib.sha256(st_text.encode('utf-8')).hexdigest()
        work = os.path.join(cache, h[:16])
        so = os.path.join(work, 'libvc.so')
        if not os.path.exists(so):
            os.makedirs(work, exist_ok=True)
            open(os.path.join(work, 'program.st'), 'w', encoding='utf-8').write(st_text)
            iec2c, lib, core_lib = compile_check.tools(openplc)
            r = subprocess.run([iec2c, '-f', '-l', '-p', '-r', '-R', '-a', '-I', lib, '-T', work, os.path.join(work, 'program.st')],
                               capture_output=True, text=True)
            if r.returncode != 0 or not os.path.exists(os.path.join(work, 'Res0.c')):
                raise RuntimeError('iec2c failed: ' + (r.stdout + r.stderr).replace(work, '<tmp>').strip()[-300:])
            open(os.path.join(work, 'vc_glue.cpp'), 'w').write(GLUE)
            r = subprocess.run(['g++', '-std=gnu++11', '-fPIC', '-shared', '-fvisibility=hidden', '-Wl,-Bsymbolic', '-w',
                                '-I', core_lib, 'Config0.c', 'Res0.c', 'vc_glue.cpp', '-o', 'libvc.so'],
                               cwd=work, capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError('g++ failed: ' + (r.stdout + r.stderr).replace(work, '<tmp>').strip()[-300:])
        self.sha = h
        self.lib = ctypes.CDLL(so, mode=os.RTLD_LOCAL)
        self.lib.vc_get.argtypes = [ctypes.c_char_p]
        self.lib.vc_get.restype = ctypes.c_int
        self.lib.vc_set.argtypes = [ctypes.c_char_p, ctypes.c_int]
        self.lib.vc_set.restype = ctypes.c_int
        self.lib.vc_ticktime.restype = ctypes.c_ulonglong
        tick = self.lib.vc_ticktime()
        if tick == 0:
            raise RuntimeError('the configuration defines no task interval')
        self.ts = tick / 1e9              # one scan per task interval of the configuration (20 ms when appended)
        self.names = {}
        self.missing = set()

    def reset(self):
        self.lib.vc_init()

    def _n(self, loc):
        if loc not in self.names:
            self.names[loc] = cname(loc).encode()
        return self.names[loc]

    def set(self, loc, v):
        if self.lib.vc_set(self._n(loc), int(v)) != 0:
            self.missing.add(loc)

    def get(self, loc):
        v = self.lib.vc_get(self._n(loc))
        if v == -99999:
            self.missing.add(loc)
            return 0
        return v

    def scan(self):
        self.lib.vc_scan()


class Bench:
    """Closed loop: every polling period the sensor values go to the input image and the output image to the plant."""

    def __init__(self, plc, plant, phase=0):
        self.plc, self.plant = plc, plant
        self.dt = plc.ts
        self.n_poll = max(1, int(round(POLL / self.dt)))
        self.k = phase
        self.t = 0.0
        plc.reset()
        self.events = []

    def press(self, button, t0, dur=PRESS):
        self.events.append((t0, button, True))
        self.events.append((t0 + dur, button, False))

    def step(self):
        for ev in [e for e in self.events if e[0] <= self.t + 1e-9]:
            self.plant.buttons[ev[1]] = ev[2]
            self.events.remove(ev)
        if self.k % self.n_poll == 0:
            for loc, v in self.plant.sensors().items():
                self.plc.set(loc, v)
            self.plant.actuate({loc: self.plc.get(loc) for loc in self.plant.actuators})
        self.k += 1
        self.plc.scan()
        self.plant.step(self.dt)
        self.t += self.dt

    def run_until(self, cond, t_max):
        while self.t < t_max - 1e-9:
            self.step()
            if cond():
                return True
        return False

    def hold(self, cond, dur):
        """True if cond holds after every step for dur seconds."""
        t_end = self.t + dur
        while self.t < t_end - 1e-9:
            self.step()
            if not cond():
                return False
        return True


# ---------------------------------------------------------------- scene models

class Conveyor:
    actuators = ['%QX100.0']

    def __init__(self, dist=2.0, box=0.4, slide=0.0):
        self.sb, self.box, self.slide = dist, box, slide
        self.fronts = []
        self.run = False
        self.buttons = {}

    def place(self):
        self.fronts.append(self.box / 2)          # the box covers sensor A at position 0

    def covers(self, f, s):
        return f - self.box <= s <= f

    def at_b(self):
        return [f for f in self.fronts if self.covers(f, self.sb)]

    def remove_at_b(self):
        self.fronts = [f for f in self.fronts if not self.covers(f, self.sb)]

    def sensors(self):
        return {'%IX100.0': any(self.covers(f, 0.0) for f in self.fronts),
                '%IX100.1': any(self.covers(f, self.sb) for f in self.fronts)}

    def actuate(self, out):
        new = bool(out['%QX100.0'])
        if self.run and not new:
            self.fronts = [f + self.slide for f in self.fronts]
        self.run = new

    def step(self, dt):
        if self.run:
            self.fronts = [f + V_CONV * dt for f in self.fronts]


class DigitalTank:
    actuators = ['%QX100.0', '%QX100.1']

    def __init__(self, delta=0.0, lag=0.0, nc_stop=False):
        self.h, self.delta, self.lag, self.nc_stop = 0.0, delta, lag, nc_stop
        self.cmd_f = self.cmd_d = 0.0
        self.vf = self.vd = 0.0
        self.buttons = {'start': False, 'stop': False}
        self.lshh_seen = False
        self.discharge_opened = False

    def lsh(self):
        return self.h >= 2.4 + self.delta

    def lshh(self):
        return self.h >= 2.7 + self.delta

    def sensors(self):
        stop = self.buttons['stop']
        return {'%IX100.0': self.buttons['start'], '%IX100.1': (not stop) if self.nc_stop else stop,
                '%IX100.2': self.lsh(), '%IX100.3': self.lshh()}

    def actuate(self, out):
        self.cmd_f, self.cmd_d = float(out['%QX100.0'] != 0), float(out['%QX100.1'] != 0)
        self.discharge_opened |= self.cmd_d > 0

    def step(self, dt):
        a = 1.0 if self.lag <= 0 else dt / (self.lag + dt)
        self.vf += (self.cmd_f - self.vf) * a
        self.vd += (self.cmd_d - self.vd) * a
        q = Q_IN * self.vf - Q_OUT * self.vd * math.sqrt(max(self.h, 0.0) / H_TANK)
        self.h = min(max(self.h + q / A_TANK * dt, 0.0), H_TANK)
        self.lshh_seen |= self.lshh()


class AnalogTank:
    actuators = ['%QW100', '%QW101']

    def __init__(self, model='B', lag=0.0, fi=1.0, fo=1.0, rounding='round', nc_stop=False, scale=100):
        self.x, self.model, self.lag, self.fi, self.fo = 0.0, model, lag, fi, fo
        self.rnd = (lambda v: int(round(v))) if rounding == 'round' else (lambda v: int(v))
        self.nc_stop, self.scale = nc_stop, scale
        self.cf = self.cd = self.vf = self.vd = 0.0
        self.buttons = {'start': False, 'stop': False}
        self.xmax = 0.0

    def sensors(self):
        stop = self.buttons['stop']
        return {'%IX100.0': self.buttons['start'], '%IX100.1': (not stop) if self.nc_stop else stop,
                '%IW100': self.rnd(self.x * 10.0 * self.scale)}

    def actuate(self, out):
        self.cf = min(max(out['%QW100'] / self.scale / 10.0, 0.0), 1.0)
        self.cd = min(max(out['%QW101'] / self.scale / 10.0, 0.0), 1.0)

    def step(self, dt):
        a = 1.0 if self.lag <= 0 else dt / (self.lag + dt)
        self.vf += (self.cf - self.vf) * a
        self.vd += (self.cd - self.vd) * a
        q_in = Q_IN * self.fi * self.vf
        q_out = Q_OUT * self.fo * self.vd * (math.sqrt(max(self.x, 0.0)) if self.model == 'B' else 1.0)
        if self.x <= 0.0:
            q_out = min(q_out, q_in)
        self.x = min(max(self.x + (q_in - q_out) / (A_TANK * H_TANK) * dt, 0.0), 1.0)
        self.xmax = max(self.xmax, self.x)


# ---------------------------------------------------------------- situations (scene_tests_en.md)

def _restart(b, loc):
    """Step-0 evidence: after a fresh start the output opens, and stop closes it again."""
    b.press('start', b.t + 1.0)
    ok = b.run_until(lambda: b.plc.get(loc) > 0, b.t + 2.0)
    b.press('stop', b.t + 0.5)
    b.run_until(lambda: False, b.t + 1.5)
    return ok and b.plc.get(loc) == 0


def _stop_latency(b, out_locs):
    """Scans from the first scan with StopCommand in the input image until every output in out_locs is 0."""
    n = 0
    while b.plc.get('%IX100.1') == 0 and n < max(100, 3 * b.n_poll):
        b.step()
        n += 1
    m = 0
    while any(b.plc.get(l) != 0 for l in out_locs) and m < 10:
        b.step()
        m += 1
    return m


def t1(plc, v):
    p = Conveyor(v.get('dist', 2.0), v.get('box', 0.4), v.get('slide', 0.0))
    b = Bench(plc, p, v.get('phase', 0))
    for i in range(5):
        if not b.hold(lambda: not p.run, 1.0):
            return False, 'box %d: conveyor running before the box was placed' % (i + 1), {}
        p.place()
        if not b.run_until(lambda: p.run, b.t + 1.0):
            return False, 'box %d: conveyor did not start within 1 s' % (i + 1), {}
        if not b.run_until(lambda: not p.run, b.t + p.sb / V_CONV + 2.0):
            return False, 'box %d: conveyor did not stop at sensor B' % (i + 1), {}
        if not p.at_b():
            return False, 'box %d: conveyor stopped before or after sensor B' % (i + 1), {}
        if not b.hold(lambda: not p.run and bool(p.at_b()), 3.0):
            return False, 'box %d: did not stay at sensor B for 3 s' % (i + 1), {}
        p.remove_at_b()
    return True, 'five boxes stopped and stayed at sensor B', {}


def t2(plc, case, v, timer):
    p = DigitalTank(v.get('delta', 0.0), v.get('lag', 0.0), v.get('nc_stop', False))
    b = Bench(plc, p, v.get('phase', 0))
    b.press('start', 1.0)
    if not b.run_until(lambda: p.cmd_f > 0, 2.0):
        return False, 'fill valve did not open within 1 s of the start', {}
    t_open = b.t
    if case == 'c':
        b.press('stop', t_open + 5.0)
        b.run_until(lambda: p.buttons['stop'], t_open + 6.0)
        lat = _stop_latency(b, ['%QX100.0'])
        ok = lat <= 1 and _restart(b, '%QX100.0')
        return ok, 'fill valve off %d scan(s) after StopCommand; restart %s' % (lat, 'ok' if ok else 'failed'), {'scans': lat}
    if not b.run_until(lambda: p.cmd_f == 0, t_open + timer + 30.0):
        return False, 'fill valve never closed', {}
    t_close, h_close, lshh_at_close = b.t, p.h, p.lshh()
    b.run_until(lambda: False, b.t + 5.0)
    h5 = p.h
    still = b.hold(lambda: p.cmd_f == 0, 5.0) and p.h - h5 <= 0.005
    restart = _restart(b, '%QX100.0')
    m = {'open_s': round(t_close - t_open, 2), 'h_close_m': round(h_close, 3)}
    if case == 'a':
        ok = abs((t_close - t_open) - timer) <= 0.5 and h_close < 2.4 + p.delta and still and restart
        return ok, 'closed after %.2f s at h = %.2f m; step 0 %s' % (t_close - t_open, h_close, 'ok' if restart else 'not reached'), m
    ok = (t_close - t_open) < timer - 0.5 and lshh_at_close and still and restart
    return ok, 'closed after %.2f s at h = %.3f m (LSHH %s); step 0 %s' % (
        t_close - t_open, h_close, 'on' if lshh_at_close else 'off', 'ok' if restart else 'not reached'), m


def t3(plc, case, v):
    p = DigitalTank(v.get('delta', 0.0), v.get('lag', 0.0), v.get('nc_stop', False))
    b = Bench(plc, p, v.get('phase', 0))
    b.press('start', 1.0)
    if not b.run_until(lambda: p.cmd_f > 0, 2.0):
        return False, 'fill valve did not open within 1 s of the start', {}
    if case == 'b':
        if not b.run_until(lambda: p.cmd_f == 0, b.t + 7.0):
            return False, 'no pause within 7 s of filling', {}
        b.press('stop', b.t + 2.0)
        ok1 = b.hold(lambda: p.cmd_f == 0, 8.0)
        b.press('start', b.t + 0.5)
        ok2 = b.run_until(lambda: p.cmd_f > 0, b.t + 2.0)
        b.press('stop', b.t + 2.0)
        b.run_until(lambda: False, b.t + 2.5)
        ok3 = b.hold(lambda: p.cmd_f == 0, 6.0)
        return ok1 and ok2 and ok3, 'stop in pause %s, restart %s, stop in filling %s' % (ok1, ok2, ok3), {}
    segs, state, t_last, t_end, t_lsh, fill_after, open_at_lsh = [], 1, b.t, None, None, 0.0, False
    while b.t < 400.0:
        b.step()
        if t_lsh is None and p.lsh():
            t_lsh, open_at_lsh = b.t, p.cmd_f > 0
        if t_lsh is not None and p.cmd_f > 0:
            fill_after += b.dt
        s = 1 if p.cmd_f > 0 else 0
        if s != state:
            segs.append((state, round(b.t - t_last, 2), b.t))
            state, t_last = s, b.t
        if t_lsh is not None and s == 0 and b.t - max(t_last, t_lsh) >= 10.0:
            t_end = t_last
            break
    # before LSH: every completed filling phase and pause lasts 5 s (the phase cut short by LSH is not counted);
    # after LSH: the fill valve stays closed, apart from at most two polling periods and a scan (0.25 s at 20 ms)
    before = [(st, d) for st, d, t_seg in segs if t_lsh is None or t_seg < t_lsh - 1e-9]
    fills = [d for st, d in before if st == 1]
    pauses = [d for st, d in before if st == 0]
    ok_alt = len(fills) >= 1 and len(pauses) >= 1 and all(abs(d - 5.0) <= 0.5 for d in fills + pauses)
    restart = t_end is not None and _restart(b, '%QX100.0')
    after_max = 2 * POLL + b.dt + 0.03
    ok = t_end is not None and ok_alt and fill_after <= after_max + 1e-9 and not p.lshh_seen and restart
    n_fill = len(fills) + (1 if open_at_lsh else 0)
    m = {'fill_phases': n_fill, 'end_s': round(t_end - 1.0, 1) if t_end else None, 'lshh': p.lshh_seen,
         'fill_after_lsh_s': round(fill_after, 2)}
    return ok, '%d filling phases before LSH, %d pauses; fill after LSH %.2f s; LSHH %s' % (
        n_fill, len(pauses), fill_after, 'reached' if p.lshh_seen else 'not reached'), m


def t4(plc, case, v):
    p = AnalogTank(v.get('model', 'B'), v.get('lag', 0.0), v.get('fi', 1.0), v.get('fo', 1.0), v.get('rounding', 'round'),
                   v.get('nc_stop', False), v.get('scale', 100))
    b = Bench(plc, p, v.get('phase', 0))
    if case == 'c':
        p.x = 0.95
        b.press('start', 1.0)
        b.run_until(lambda: False, 2.0)                  # 1 s after the start was pressed
        ok = b.hold(lambda: p.cf == 0 and p.cd == 0, 6.0)
        return ok, 'valves closed within 1 s and kept closed' if ok else 'valves not closed and kept closed', {}
    b.press('start', 1.0)
    if not b.run_until(lambda: p.cf > 0 or p.cd > 0, 2.0):
        return False, 'no valve opened within 1 s of the start', {}
    t0 = b.t
    if case == 'b':
        b.press('stop', t0 + 40.0)
        b.run_until(lambda: p.buttons['stop'], t0 + 41.0)
        lat = _stop_latency(b, ['%QW100', '%QW101'])
        ok = lat <= 1 and _restart(b, '%QW101')
        return ok, 'both outputs 0 %d scan(s) after StopCommand; restart %s' % (lat, 'ok' if ok else 'failed'), {'scans': lat}
    while b.t < t0 + 900.0:
        b.step()
        if p.cf == 0 and p.cd == 0 and b.t - t0 > 1.0:
            break
    t_end, x_end = b.t, p.x
    ended = t_end - t0 < 900.0
    restart = ended and _restart(b, '%QW101')
    m = {'end_s': round(t_end - t0, 1), 'x_max': round(p.xmax, 3), 'overshoot': round(max(0.0, p.xmax - 0.8), 3),
         'error_end': round(0.8 - x_end, 3)}
    ok = p.xmax < 0.9 and ended and abs(0.8 - x_end) <= 0.02 + 1e-9 and restart
    if not ended:
        return ok, 'did not end within 900 s; highest level %.3f' % p.xmax, m
    return ok, 'ended after %.1f s; highest level %.3f; end error %.3f; step 0 %s' % (
        t_end - t0, p.xmax, 0.8 - x_end, 'ok' if restart else 'not reached'), m


SITUATIONS = {'T1': ['scene'], 'T2': ['a', 'b', 'c'], 'T3': ['a', 'b'], 'T4': ['a', 'b', 'c']}
VARIANTS = {  # alternative assumptions for --sensitivity (the verdict always uses the nominal model, {})
    'T1': {'A-B 0.6 m': {'dist': 0.6}, 'A-B 4 m': {'dist': 4.0}, 'box 0.3 m, slide 0.1 m': {'box': 0.3, 'slide': 0.1},
           'polling phase 40 ms': {'phase': 2}},
    'T2': {'switches -0.05 m': {'delta': -0.05}, 'switches +0.05 m': {'delta': 0.05}, 'valve lag 1 s': {'lag': 1.0},
           'polling phase 40 ms': {'phase': 2}},
    'T3': {'switches -0.05 m': {'delta': -0.05}, 'switches +0.05 m': {'delta': 0.05}, 'valve lag 1 s': {'lag': 1.0},
           'polling phase 40 ms': {'phase': 2}},
    'T4': {'outflow independent of level': {'model': 'A'}, 'valve lag 2 s': {'lag': 2.0},
           'inflow x0.8': {'fi': 0.8}, 'registers truncated': {'rounding': 'trunc'}},
}


def run_situation(plc, task, case, v):
    if task == 'T1':
        return t1(plc, v)
    if task == 'T2':
        return t2(plc, case, v, 60.0 if case == 'b' else 15.0)
    if task == 'T3':
        return t3(plc, case, v)
    return t4(plc, case, v)


def test_program(src_text, task, openplc, cache, variants=None):
    """All situations of one program under the nominal model (and optional variants).  Returns (verdict, log, result)."""
    log, result = [], {'task': task, 'scene_model': SCENE_MODEL, 'situations': {}, 'sensitivity': {}}
    tmp = os.path.join(cache, 'src.st')
    open(tmp, 'w', encoding='utf-8').write(src_text)
    wrapped, note, _ = compile_check.prepare(tmp)
    log.append('preparation: %s' % note)
    if wrapped is None:
        log.append('verdict: 0 (nothing the runtime could run)')
        return 0, log, result
    verdict = 1
    missing, intervals = set(), set()
    runs = [('nominal', {})] + sorted((variants or {}).items())
    for label, v in runs:
        passed = 0
        for case in SITUATIONS[task]:
            text = wrapped
            if task != 'T1':
                text, plog = set_params.set_params(wrapped, set_params.SCENARIOS[(task, case)])
                if label == 'nominal':
                    log.extend('   %s (%s): %s' % (task, case, l) for l in plog)
            try:
                plc = PLC(text, openplc, cache)
                intervals.add(plc.ts)
                ok, detail, metrics = run_situation(plc, task, case, v)
                missing |= plc.missing
            except Exception as e:                        # build or load failure of a compiled program
                ok, detail, metrics = False, 'not testable: %s' % e, {}
            passed += ok
            if label == 'nominal':
                verdict &= ok
                log.append('%s (%s): %s - %s' % (task, case, 'pass' if ok else 'FAIL', detail))
                result['situations'][case] = {'pass': bool(ok), 'detail': detail, 'metrics': metrics}
            else:
                result['sensitivity'].setdefault(label, {})[case] = bool(ok)
        if label != 'nominal':
            log.append('sensitivity, %s: %d/%d situations pass' % (label, passed, len(SITUATIONS[task])))
    if missing:
        log.append('I/O not declared by the program (not connected): %s' % ', '.join(sorted(missing)))
    if intervals:
        log.append('task interval of the configuration: %s' % ', '.join('%g ms' % (x * 1e3) for x in sorted(intervals)))
    log.append('verdict: %d' % verdict)
    result['verdict'] = verdict
    return verdict, log, result


# ---------------------------------------------------------------- command line

def one(a):
    """Test one program in this process; print the log; write JSON if asked."""
    cache = tempfile.mkdtemp(prefix='scene_')
    try:
        src = open(a.file, encoding='utf-8', errors='replace').read()
        head = ['file: %s  sha256: %s' % (a.shown or os.path.basename(a.file), hashlib.sha256(src.encode()).hexdigest()),
                'task: %s; %s; OpenPLC_v3 commit: %s' % (a.task, SCENE_MODEL, compile_check.versions(a.openplc, compile_check.tools(a.openplc)[0])[0].split(': ')[-1])]
        verdict, log, result = test_program(src, a.task, a.openplc, cache, VARIANTS[a.task] if a.sensitivity else None)
        print('\n'.join(head + log))
        if a.json:
            json.dump(result, open(a.json, 'w'), indent=1)
        return verdict
    finally:
        shutil.rmtree(cache, ignore_errors=True)


def isolated(openplc, path, task, shown, sensitivity, timeout=300):
    """Run one program in a child process, so that a program that never ends its scan or crashes fails cleanly."""
    out = tempfile.mktemp(prefix='scene_', suffix='.json')
    cmd = [sys.executable, '-I', os.path.abspath(__file__), '--openplc', openplc, '--file', path, '--task', task,
           '--shown', shown, '--json', out] + (['--sensitivity'] if sensitivity else [])
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        text = r.stdout.strip()
        if os.path.exists(out):
            result = json.load(open(out))
            return result.get('verdict', 0), text, result
        return 0, text + '\nverdict: 0 (the test ended abnormally: %s)' % (r.stderr.strip()[-200:] or 'exit %d' % r.returncode), {}
    except subprocess.TimeoutExpired:
        return 0, 'file: %s\nverdict: 0 (no result within %d s: a scan did not return)' % (shown, timeout), {}
    finally:
        if os.path.exists(out):
            os.remove(out)


def run_csv(a):
    rows = list(csv.DictReader(open(a.runs, encoding='utf-8')))
    if not rows:
        sys.exit('%s has no rows' % a.runs)
    fields = list(rows[0].keys())
    counts = {}
    sens_rows = []
    for r in rows:
        jobs = [('scene_test_pass', 'st_code', 'compiled', 'A1' if r['condition'] == 'workflow' else 'baseline')]
        if r['condition'] == 'workflow':
            jobs.append(('a2_scene_test_pass', 'a2_st_code', 'a2_compiled', 'A2'))
        parts = []
        for col, path_col, comp_col, label in jobs:
            rel = r.get(path_col, '').strip()
            path = os.path.join(a.base, rel)
            compiled = r.get(comp_col, '').strip()
            if not rel or not os.path.isfile(path) or compiled == '':
                continue
            if compiled != '1':
                r[col] = '0'
                parts.append('== %s (%s) ==\nnot compiled: not scene-tested, %s = 0' % (label, path_col, col))
                verdict = 0
            else:
                verdict, text, result = isolated(a.openplc, path, r['task_id'], rel, a.sensitivity)
                r[col] = str(verdict)
                parts.append('== %s (%s) ==\n%s' % (label, path_col, text))
                for var, cases in result.get('sensitivity', {}).items():
                    sens_rows.append({'run_id': r['run_id'], 'program': label, 'variant': var,
                                      'all_situations_pass': int(all(cases.values()))})
            counts.setdefault((r['task_id'], r['condition'], label), [0, 0])[verdict] += 1
        if parts and a.write and r.get('test_log', '').strip():
            log_path = os.path.join(a.base, r['test_log'].strip())
            os.makedirs(os.path.dirname(log_path) or '.', exist_ok=True)
            open(log_path, 'w', encoding='utf-8').write('\n\n'.join(parts) + '\n')
    print('task condition program  pass  fail')
    for k in sorted(counts):
        print('%-4s %-9s %-8s %4d  %4d' % (k[0], k[1], k[2], counts[k][1], counts[k][0]))
    if a.write:
        shutil.copyfile(a.runs, a.runs + '.bak')
        w = csv.DictWriter(open(a.runs, 'w', encoding='utf-8', newline=''), fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
        print('updated', a.runs, '(previous version kept as %s.bak)' % a.runs)
        if sens_rows:
            out = os.path.join(os.path.dirname(os.path.abspath(a.runs)), 'scene_sensitivity.csv')
            w = csv.DictWriter(open(out, 'w', encoding='utf-8', newline=''), fieldnames=list(sens_rows[0].keys()))
            w.writeheader()
            w.writerows(sens_rows)
            print('wrote', out)


SELFTEST = {  # programs that must fail every situation (no task-card solution is shipped)
    'T1 conveyor always on': ('T1', 'PROGRAM Main\n  VAR\n    Conveyor AT %QX100.0 : BOOL;\n  END_VAR\n  Conveyor := TRUE;\nEND_PROGRAM\n'),
    'T1 conveyor never on': ('T1', 'PROGRAM Main\n  VAR\n    Conveyor AT %QX100.0 : BOOL;\n  END_VAR\n  Conveyor := FALSE;\nEND_PROGRAM\n'),
    'T2 fill valve always open': ('T2', 'PROGRAM Main\n  VAR\n    FillValve AT %QX100.0 : BOOL;\n  END_VAR\n  FillValve := TRUE;\nEND_PROGRAM\n'),
    'T3 no I/O declared': ('T3', 'PROGRAM Main\n  VAR\n    x : BOOL;\n  END_VAR\n  x := NOT x;\nEND_PROGRAM\n'),
    'T4 valves fully open': ('T4', 'PROGRAM Main\n  VAR\n    FillValve AT %QW100 : INT;\n    DischargeValve AT %QW101 : INT;\n'
                                   '  END_VAR\n  FillValve := 1000;\n  DischargeValve := 400;\nEND_PROGRAM\n'),
}


_T1_LATCH = ('PROGRAM Main\n  VAR\n    SensorA AT %IX100.0 : BOOL;\n    SensorB AT %IX100.1 : BOOL;\n'
             '    Conveyor AT %QX100.0 : BOOL;\n  END_VAR\n  VAR\n    latch : RS;\n  END_VAR\n'
             '  latch(S := SensorA, R1 := SensorB);\n  Conveyor := latch.Q1;\nEND_PROGRAM\n'
             'CONFIGURATION Config0\n  RESOURCE Res0 ON PLC\n    TASK task0(INTERVAL := {INTERVAL}, PRIORITY := 0);\n'
             '    PROGRAM instance0 WITH task0 : Main;\n  END_RESOURCE\nEND_CONFIGURATION\n')
SELFTEST_PASS = {  # a program that brings its own configuration runs at its own task interval and must pass
    'T1 latch, own task 100 ms': ('T1', _T1_LATCH.replace('{INTERVAL}', 'T#100ms')),
    'T1 latch, own task 10 ms': ('T1', _T1_LATCH.replace('{INTERVAL}', 'T#10ms')),
}


def selftest(a):
    """Plant sanity, programs that must fail every situation, and programs with their own task interval that must pass."""
    ok = True
    p = DigitalTank()
    p.cmd_f = 1.0
    t = 0.0
    while not p.lsh():
        p.step(TS)
        t += TS
    sane = abs(t - 2.4 * A_TANK / Q_IN) < 0.05
    print('%-4s plant: digital tank reaches LSH after %.2f s with the fill valve open (expected %.2f s)'
          % ('ok' if sane else 'FAIL', t, 2.4 * A_TANK / Q_IN))
    ok &= sane
    cache = tempfile.mkdtemp(prefix='scene_')
    try:
        for name, (task, text) in SELFTEST.items():
            verdict, log, result = test_program(text, task, a.openplc, cache)
            fails = [c for c, s in result['situations'].items() if not s['pass']]
            good = verdict == 0 and len(fails) == len(SITUATIONS[task])
            ok &= good
            print('%-4s %-28s verdict %d, situations failed %d/%d' % ('ok' if good else 'FAIL', name, verdict, len(fails), len(SITUATIONS[task])))
        for name, (task, text) in SELFTEST_PASS.items():
            verdict, log, result = test_program(text, task, a.openplc, cache)
            good = verdict == 1
            ok &= good
            print('%-4s %-28s verdict %d (%s)' % ('ok' if good else 'FAIL', name, verdict, log[-2]))
    finally:
        shutil.rmtree(cache, ignore_errors=True)
    print('selftest:', 'passed' if ok else 'FAILED')
    return ok


def main():
    ap = argparse.ArgumentParser(description='Scene tests by closed-loop simulation (no Factory I/O needed).')
    ap.add_argument('runs', nargs='?')
    ap.add_argument('--openplc', required=True, help='OpenPLC_v3 folder at the pinned commit, with matiec built')
    ap.add_argument('--base', default='.')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--file')
    ap.add_argument('--task', choices=['T1', 'T2', 'T3', 'T4'])
    ap.add_argument('--shown', help=argparse.SUPPRESS)
    ap.add_argument('--json')
    ap.add_argument('--sensitivity', action='store_true')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest(a) else 1)
    if a.file:
        if not a.task:
            ap.error('--file needs --task')
        sys.exit(0 if one(a) else 1)
    if a.runs:
        run_csv(a)
    else:
        ap.error('give runs.csv, --file with --task, or --selftest')


if __name__ == '__main__':
    main()
