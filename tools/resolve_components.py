#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Resolve Nival's component graph (.application/.component) into a CMake fragment.

The published Prime World tree describes every executable with Nival's own build
description language: an `.application` root that lists `sources` and `components`,
and one `.component` per module doing the same recursively.  The files are Python
snippets executed by Tools/TestFramework (Python 2) with a handful of globals
injected; Tools/CMakeGenerator/main.py is Nival's own (Python 2) CMake emitter and
this script is a Python 3 re-implementation of its resolution rules:

  * a component name is looked up as
        <path>/<name>.component
        <path>/<name>.application
        <path>/<name>/all.component
        <path>/<name>/<basename(name)>.component
    against, in order, the *referencing* component's own directory and then the
    global scope from unittest.cfg:  Src, ., Src/Server, Src/Game/PF, Tools
  * `sources` is relative to the component's own directory and may be a list or a
    dict-of-lists (that is what getDefaultSources returns)
  * `includePaths` is relative to the component's directory, and '.' is implicit
  * RPCBuilder('Local'|'Remote', 'IFace.h', ...) generates L/RIFace.auto.{h,cpp}
    next to the header; those generated files are committed in the published tree,
    so we add whichever of them exist on disk.

Output is a .cmake file with PWCI_SRV_SRCS / _INCDIRS / _LIBS / _DEFS.
"""

import argparse
import fnmatch
import os
import string
import sys

SCOPE = ['Src', '.', 'Src/Server', 'Src/Game/PF', 'Tools']

# Vendor/Libc is referenced by ~120 components and is nothing but the CRT; the published
# tree ships Vendor/Libc/README.txt with the descriptor removed. Not worth a warning.
BENIGN_MISSING = {'Vendor/Libc'}

TEMPLATES = [
    '{path}/{name}.component',
    '{path}/{name}.application',
    '{path}/{name}/all.component',
    '{path}/{name}/{short}.component',
]

SRC_EXT = ('.cpp', '.c', '.cc', '.cxx')


class _Stub(object):
    def __init__(self, *a, **kw):
        self.args = a
        self.kwargs = kw

    def get(self, *a, **kw):
        return None

    def __setattr__(self, k, v):
        object.__setattr__(self, k, v)

    def __getattr__(self, k):
        return None

    def __call__(self, *a, **kw):
        return _Stub(*a, **kw)


class RPCBuilderStub(object):
    def __init__(self, typename=None, filename=None, flt='', includes=None):
        self.typename = typename
        self.filename = filename


class Component(object):
    def __init__(self, name, descriptor):
        self.name = name
        self.descriptor = descriptor
        self.dir = os.path.dirname(descriptor)
        self.sources = []
        self.include_paths = []
        self.libs = []
        self.defines = []
        self.local_keys = []
        self.children = []
        self.pch = None
        self.pch_set = []


def _collect_files(start, patterns, ignored, recursive):
    out = []
    for root, dirs, files in os.walk(start):
        for name in files:
            rel = os.path.join(root, name)[len(start) + 1:]
            if any(fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(name, p) for p in patterns):
                if any(fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(name, p) for p in ignored):
                    continue
                out.append(os.path.join(root, name))
        if not recursive:
            break
    return out


def _py2_open(name, mode='r', *a, **kw):
    return open(name, mode.replace('b', '') or 'r', errors='replace')


def load_descriptor(path, platform='win32', configuration='release'):
    """exec the component file the way Nival's loader does, return its locals."""
    directory = os.path.dirname(path)
    settings = _Stub()

    def get_default_sources(patterns, ignored=(), recursive=True):
        files = _collect_files(directory, list(patterns), list(ignored), recursive)
        res = {}
        for f in files:
            key = os.path.dirname(os.path.relpath(f, directory)).replace('\\', '/')
            res.setdefault(key, []).append(os.path.relpath(f, directory))
        return res

    g = {
        '__builtins__': __builtins__,
        'os': os,
        'sys': sys,
        'string': string,
        'settings': settings,
        'configuration': configuration,
        'platform': platform,
        'testRun': False,
        'compiler': 'msvc9',
        'descriptorPath': directory,
        'workingDirectory': directory,
        'Win32Features': _Stub,
        'LinuxFeatures': _Stub,
        'MacFeatures': _Stub,
        'RPCBuilder': RPCBuilderStub,
        'CodeGen': _Stub,
        'ThriftBuilder': _Stub,
        'InstallBuilder': _Stub,
        'CopyBuilder': _Stub,
        'getDefaultSources': get_default_sources,
        # Python 2 read text out of 'rb' handles; a couple of descriptors
        # (Vendor/wsdlpull) parse makefiles that way.
        'open': _py2_open,
    }
    with open(path, 'r') as fh:
        code = fh.read()
    # several descriptors (Vendor/wsdlpull) read files with paths relative to the
    # descriptor's own directory, exactly like Nival's loader which chdir'd first.
    # One namespace for globals and locals: descriptors written for Python 2 rely on
    # module-level names being visible inside comprehensions (Vendor/Thrift does), which
    # only holds when globals is locals.
    saved = os.getcwd()
    try:
        os.chdir(directory)
        exec(compile(code, path, 'exec'), g)
    finally:
        os.chdir(saved)
    return g


class Resolver(object):
    def __init__(self, root, verbose=False):
        self.root = os.path.abspath(root)
        self.scope = [os.path.normpath(os.path.join(self.root, p)) for p in SCOPE]
        self.verbose = verbose
        self.by_descriptor = {}
        self.missing = []

    def find(self, base_dir, name):
        name = name.replace('\\', '/')
        short = os.path.basename(name)
        for path in [base_dir] + self.scope:
            for tmpl in TEMPLATES:
                cand = os.path.normpath(tmpl.format(path=path, name=name, short=short))
                if os.path.isfile(cand):
                    return cand
        return None

    def load(self, descriptor, name):
        descriptor = os.path.normpath(descriptor)
        if descriptor in self.by_descriptor:
            return self.by_descriptor[descriptor]

        comp = Component(name, descriptor)
        self.by_descriptor[descriptor] = comp

        try:
            l = load_descriptor(descriptor)
        except Exception as exc:                      # noqa: BLE001
            sys.stderr.write('WARN: cannot evaluate %s: %r\n' % (descriptor, exc))
            return comp

        raw = l.get('sources', [])
        names = []
        if isinstance(raw, dict):
            for vals in raw.values():
                names.extend(vals)
        else:
            names.extend(raw)

        for s in names:
            s = s.replace('\\', '/')
            if not s.lower().endswith(SRC_EXT):
                continue
            full = os.path.normpath(os.path.join(comp.dir, s))
            if os.path.isfile(full):
                comp.sources.append(full)
            else:
                sys.stderr.write('WARN: %s: source not on disk: %s\n' % (descriptor, s))

        # generated RPC glue that ships in the tree
        for b in l.get('builders', []) or []:
            if not isinstance(b, RPCBuilderStub) or not b.filename:
                continue
            base = os.path.splitext(os.path.basename(b.filename))[0]
            prefix = {'Local': 'L', 'Remote': 'R'}.get(b.typename)
            if prefix is None:
                continue
            gen = os.path.normpath(os.path.join(
                comp.dir, os.path.dirname(b.filename.replace('\\', '/')),
                '%s%s.auto.cpp' % (prefix, base)))
            if os.path.isfile(gen):
                comp.sources.append(gen)

        comp.include_paths.append(comp.dir)
        for p in l.get('includePaths', []) or []:
            comp.include_paths.append(os.path.normpath(os.path.join(comp.dir, p.replace('\\', '/'))))
        for p in l.get('localIncludePaths', []) or []:
            comp.include_paths.append(os.path.normpath(os.path.join(comp.dir, p.replace('\\', '/'))))

        for lib in (l.get('libs', []) or []) + (l.get('libDependencies', []) or []):
            comp.libs.append(lib.replace('.lib', ''))

        # Nival's CombineCompilerKeys merges an inlined component's compilerKeys into its
        # parent, and every component here is inlined (inlined defaults to True), so
        # globalCompilerKeys / compilerKeys / defines all end up project-wide in a monolith.
        # localCompilerKeys / localDefines are the exception - componentAnalyzer.py:637 puts
        # those on the component's own files only (Vendor/Thrift's NOMINMAX is one, and it
        # must not leak into game code that uses the windows.h min/max macros).
        for key in ('globalCompilerKeys', 'compilerKeys'):
            for k in l.get(key, []) or []:
                comp.defines.append(k)
        for key in ('globalDefines', 'defines'):
            for d in l.get(key, []) or []:
                comp.defines.append('/D ' + d)
        for k in l.get('localCompilerKeys', []) or []:
            comp.local_keys.append(k)
        for d in l.get('localDefines', []) or []:
            comp.local_keys.append('/D ' + d)

        # Nival compiled every component with /FI"<generated pch>" where the generated
        # header just #includes whatever platformFeatures declared (see
        # Tools/TestFramework/platforms.py Win32Features.Apply). Without it the sources
        # that rely on the pch for their common includes do not compile standalone.
        pf = l.get('platformFeatures') or {}
        feature = pf.get('win32') if isinstance(pf, dict) else None
        pch_name = None
        if feature is not None:
            a = getattr(feature, 'args', None)
            if a:
                pch_name = a[0]
        if pch_name:
            rel = pch_name.replace('\\', '/')
            cand = os.path.normpath(os.path.join(comp.dir, rel))
            if not os.path.isfile(cand):
                # a few descriptors still spell the path from the old directory layout
                # (Game/PF/Server/GameChatController says 'GameChatController\stdafx.h')
                cand = os.path.normpath(os.path.join(comp.dir, os.path.basename(rel)))
            if os.path.isfile(cand):
                comp.pch = cand

        for child_name in l.get('components', []) or []:
            child_name = child_name.replace('\\', '/')
            found = self.find(comp.dir, child_name)
            if not found:
                if child_name not in BENIGN_MISSING:
                    self.missing.append((child_name, descriptor))
                continue
            child = self.load(found, child_name)
            comp.children.append(child)

        return comp

    def resolve(self, app_path):
        app_path = os.path.abspath(app_path)
        return self.load(app_path, os.path.splitext(os.path.basename(app_path))[0])


def cm(path):
    return path.replace('\\', '/')


def normalise_keys(keys):
    """Turn Nival compilerKeys into things add_definitions() can take.

    The lists mix real preprocessor keys ('/D FOO', '/DFOO=1', '/D"FOO"') with codegen
    flags ('/MD', '/Zi', '/EHa') that CMAKE_CXX_FLAGS already owns and must not be
    duplicated.  Keep -D and /wd only.
    """
    out = []
    pending_d = False
    for raw in keys:
        for tok in raw.split():
            if pending_d:
                out.append('-D' + tok.strip('"'))
                pending_d = False
                continue
            if tok == '/D' or tok == '-D':
                pending_d = True
            elif tok.startswith('/D') or tok.startswith('-D'):
                out.append('-D' + tok[2:].strip('"'))
            elif tok.startswith('/wd'):
                out.append(tok)
    seen, uniq_out = set(), []
    for x in out:
        if x not in seen:
            seen.add(x)
            uniq_out.append(x)
    return uniq_out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True, help='branch root that holds Src/ and unittest.cfg')
    ap.add_argument('--app', required=True, help='root .application/.component descriptor')
    ap.add_argument('--out', required=True, help='.cmake file to write')
    ap.add_argument('--prefix', default='PWCI_SRV')
    ap.add_argument('--pch-out', help='generated union precompiled header (default: <out>_pch.h)')
    ap.add_argument('--list-components', action='store_true')
    args = ap.parse_args()

    r = Resolver(args.root)
    root = r.resolve(args.app)

    # Post-order: a component's dependencies are emitted before the component itself.
    # MSVC runs global constructors in link order, so this reproduces the bottom-up order
    # of Nival's DLL build instead of the alphabetical order a GLOB would give.
    ordered, seen = [], set()

    def walk(c):
        if c.descriptor in seen:
            return
        seen.add(c.descriptor)
        for child in c.children:
            walk(child)
        ordered.append(c)

    walk(root)
    for c in r.by_descriptor.values():        # anything unreachable from root (cannot happen)
        walk(c)

    # Precompiled headers, the way Tools/TestFramework does it
    # (componentAnalyzer.Component.RemoveDummyDependencies -> ApplyPlatformFeatures ->
    # platforms.Win32Features.Apply). Depth first: a component first merges the
    # platformFeatures of every inlined child into its own, then force-includes a generated
    # header holding that whole union into *its own* sources - the children's sources have
    # already been given their own, narrower union one level down. A component whose subtree
    # declares no pch at all gets no forced include, exactly as in Nival's build.
    for comp in ordered:
        merged = []
        for child in comp.children:
            for h in child.pch_set:
                if h not in merged:
                    merged.append(h)
        if comp.pch and comp.pch not in merged:
            merged.append(comp.pch)
        comp.pch_set = merged

    srcs, incs, libs, defs = [], [], [], []
    local_groups = []
    pch_groups = []
    claimed = set()
    for comp in ordered:
        own = [x for x in comp.sources if x not in claimed]
        claimed.update(own)
        srcs.extend(comp.sources)
        incs.extend(comp.include_paths)
        libs.extend(comp.libs)
        defs.extend(comp.defines)
        if comp.pch_set and own:
            pch_groups.append((tuple(comp.pch_set), own))
        if comp.local_keys and own:
            local_groups.append((normalise_keys(comp.local_keys), own))

    def uniq(seq):
        seen, out = set(), []
        for x in seq:
            if x not in seen:
                seen.add(x)
                out.append(x)
        return out

    srcs, incs, libs = uniq(srcs), uniq(incs), uniq(libs)
    defs = normalise_keys(defs)

    if args.list_components:
        for c in ordered:
            print('%-4d %s' % (len(c.sources), os.path.relpath(c.descriptor, args.root)))

    for name, where in r.missing:
        sys.stderr.write('MISSING COMPONENT: %s (referenced by %s)\n'
                         % (name, os.path.relpath(where, args.root)))

    # One generated header per distinct pch union, named after its index; Nival keyed the
    # same cache by a hash of the set (platforms.Win32Features.DeteminePCH).
    base = args.pch_out or os.path.splitext(args.out)[0] + '_pch'
    pch_files = {}
    for headers, _files in pch_groups:
        if headers in pch_files:
            continue
        path = '%s%d.h' % (base, len(pch_files))
        pch_files[headers] = path
        with open(path, 'w') as fh:
            fh.write('// generated by tools/resolve_components.py - do not edit\n')
            fh.write('#pragma once\n')
            for h in headers:
                fh.write('#include "%s"\n' % cm(h))

    covered = sum(len(f) for _h, f in pch_groups)

    p = args.prefix
    with open(args.out, 'w') as fh:
        fh.write('# generated by tools/resolve_components.py from %s\n'
                 % cm(os.path.relpath(args.app, args.root)))
        fh.write('# %d components, %d sources, %d pch variants covering %d sources\n\n'
                 % (len(r.by_descriptor), len(srcs), len(pch_files), covered))
        for var, items in (('%s_SRCS' % p, srcs), ('%s_INCDIRS' % p, incs)):
            fh.write('set( %s\n' % var)
            for i in items:
                fh.write('  "%s"\n' % cm(i))
            fh.write(')\n\n')
        fh.write('set( %s_LIBS %s )\n' % (p, ' '.join(libs)))
        fh.write('set( %s_DEFS %s )\n' % (p, ' '.join(defs)))
        fh.write('\nmacro( %s_apply_pch )\n' % p)
        for headers, files in pch_groups:
            files = [f for f in files if not f.lower().endswith('.c')]
            if not files:
                continue
            fh.write('  set_source_files_properties(\n')
            for f in files:
                fh.write('    "%s"\n' % cm(f))
            fh.write('    PROPERTIES COMPILE_FLAGS "/FI\\"%s\\""\n  )\n'
                     % cm(pch_files[headers]))
        for keys, files in local_groups:
            if not keys:
                continue
            fh.write('  set_source_files_properties(\n')
            for f in files:
                fh.write('    "%s"\n' % cm(f))
            fh.write('    PROPERTIES COMPILE_FLAGS "%s"\n  )\n'
                     % ' '.join(k.replace('-D', '/D') for k in keys))
        fh.write('endmacro()\n')

    sys.stderr.write('resolved %d components, %d sources, %d include dirs, '
                     '%d pch variants covering %d sources, %d missing\n'
                     % (len(r.by_descriptor), len(srcs), len(incs),
                        len(pch_files), covered, len(r.missing)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
