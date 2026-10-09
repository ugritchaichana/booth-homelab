"""Condition coverage: run a test directory against an instrumented module and require every atomic condition of every decision to be seen both true and false."""
import argparse
import ast
import sys
import types
import unittest
from pathlib import Path


class Instrument(ast.NodeTransformer):
    def __init__(self):
        self.sites = []

    def condition(self, node):
        if isinstance(node, ast.BoolOp):
            node.values[-1] = self.condition(node.values[-1])
            return node
        if isinstance(node, (ast.Constant, ast.List, ast.Tuple, ast.Dict, ast.Set)):
            return node
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            node.operand = self.condition(node.operand)
            return node
        self.sites.append((node.lineno, ast.unparse(node)))
        call = ast.Call(func=ast.Name("_condition", ast.Load()), args=[ast.Constant(len(self.sites) - 1), node], keywords=[])
        return ast.copy_location(call, node)

    def visit_BoolOp(self, node):
        self.generic_visit(node)
        node.values[:-1] = [self.condition(value) for value in node.values[:-1]]
        return node

    def visit_If(self, node):
        self.generic_visit(node)
        if not is_main_guard(node.test):
            node.test = self.condition(node.test)
        return node

    visit_While = visit_If

    def visit_IfExp(self, node):
        self.generic_visit(node)
        node.test = self.condition(node.test)
        return node

    def visit_comprehension(self, node):
        self.generic_visit(node)
        node.ifs = [self.condition(test) for test in node.ifs]
        return node


def is_main_guard(test):
    return isinstance(test, ast.Compare) and ast.unparse(test) in ("__name__ == '__main__'", '__name__ == "__main__"')


def instrumented(path, name):
    instrument = Instrument()
    tree = ast.fix_missing_locations(instrument.visit(ast.parse(Path(path).read_text(encoding="utf-8"), str(path))))
    seen = [set() for _ in instrument.sites]

    def record(site, value):
        seen[site].add(bool(value))
        return value

    module = types.ModuleType(name)
    module.__file__ = str(path)
    module._condition = record
    exec(compile(tree, str(path), "exec"), module.__dict__)
    return module, instrument.sites, seen


def missing(sites, seen):
    return [(line, text, sorted(outcomes)) for (line, text), outcomes in zip(sites, seen) if outcomes != {False, True}]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module")
    parser.add_argument("tests")
    parser.add_argument("--fail-under", type=float, default=100.0)
    args = parser.parse_args(argv)
    name = Path(args.module).stem
    sys.path.insert(0, str(Path(args.module).resolve().parent))
    module, sites, seen = instrumented(args.module, name)
    sys.modules[name] = module
    result = unittest.TextTestRunner(verbosity=0).run(unittest.defaultTestLoader.discover(args.tests))
    gaps = missing(sites, seen)
    covered = len(sites) - len(gaps)
    percent = 100.0 * covered / len(sites) if sites else 100.0
    print(f"conditions {covered} of {len(sites)} seen both true and false ({percent:.2f}%)")
    for line, text, outcomes in gaps:
        print(f"  line {line}: {text} seen only {outcomes}")
    return 0 if result.wasSuccessful() and percent >= args.fail_under else 1


if __name__ == "__main__":
    sys.exit(main())
