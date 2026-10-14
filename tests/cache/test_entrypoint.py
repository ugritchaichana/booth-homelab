import runpy
import unittest
from unittest import mock

from support import REPO  # noqa: F401  (puts scripts/ci on sys.path)


class EntrypointTests(unittest.TestCase):
    def test_python_dash_m_exits_with_the_status_the_cli_returns(self):
        for status in (0, 3):
            with mock.patch("build_cache.cli.main", return_value=status) as main:
                with self.assertRaises(SystemExit) as raised:
                    runpy.run_module("build_cache", run_name="__main__", alter_sys=True)
            self.assertEqual(raised.exception.code, status)
            main.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
