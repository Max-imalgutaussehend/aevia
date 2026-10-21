"""Handover API: auth, validation, branch creation, runner call. Local bare repositories and a fake runner, no network.
Run: python3 -m unittest discover -s tests/handover-api"""
import json, os, socket, stat, subprocess, sys, tempfile, textwrap, time, unittest, urllib.error, urllib.request
from pathlib import Path

API = Path(__file__).resolve().parents[2] / "agents/herdr/image/aevia-handover-api"
TMP = Path(tempfile.mkdtemp())
RUNNER = TMP / "runner"
RUNNER.write_text("\n".join([
    "#!/bin/bash",
    'echo "$@" >> "$RUNNER_LOG"',
    'case "$1" in',
    '  start) echo "started $4 on $3 (pid 1)" ;;',
    "  status) printf 'slug:     %s\\nstatus:   done\\nstarted:  2026-10-21T10:00:00Z\\nfinished: 2026-10-21T10:05:00Z\\ncommits:\\n  abc123 handover(x): agent work and result\\nresult:   .handover/x/RESULT.md is present\\n' \"$2\" ;;",
    "  result) printf -- '---\\nstatus: done\\n---\\n## Done\\nall of it\\n' ;;",
    "  list) printf 'alpha                    running\\nbeta                     done\\n' ;;",
    '  stop) echo "stopped $2" ;;',
    "esac", ""]))
RUNNER.chmod(RUNNER.stat().st_mode | stat.S_IEXEC)
TOKEN = "test-token"


def git(*a, cwd=None):
    return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=cwd, check=True, capture_output=True, text=True).stdout


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0)); return s.getsockname()[1]


class Api(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        bare = TMP / "github.com/Max-imalgutaussehend/demo.git"
        bare.parent.mkdir(parents=True)
        git("init", "-q", "--bare", "-b", "main", str(bare))
        seed = TMP / "seed"
        git("clone", "-q", str(bare), str(seed))
        (seed / "README.md").write_text("demo\n")
        git("add", "-A", cwd=seed); git("commit", "-q", "-m", "init", cwd=seed); git("push", "-q", "origin", "HEAD:main", cwd=seed)
        cls.bare, cls.port = bare, free_port()
        env = {**os.environ, "HANDOVER_API_TOKEN": TOKEN, "HANDOVER_API_PORT": str(cls.port), "HANDOVER_RUNNER": str(RUNNER),
               "HANDOVER_GIT_PREFIX": f"file://{TMP}/", "RUNNER_LOG": str(TMP / "runner.log")}
        cls.proc = subprocess.Popen([sys.executable, str(API)], env=env)
        for _ in range(50):
            try: socket.create_connection(("127.0.0.1", cls.port), 0.2).close(); break
            except OSError: time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate(); cls.proc.wait()

    def call(self, method, path, body=None, token=TOKEN):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", method=method, data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Authorization": f"Bearer {token}"} if token else {})
        try:
            with urllib.request.urlopen(req, timeout=30) as r: return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e: return e.code, json.loads(e.read())

    def test_needs_the_token(self):
        self.assertEqual(self.call("GET", "/list", token=None)[0], 401)
        self.assertEqual(self.call("GET", "/list", token="wrong")[0], 401)

    def test_refuses_to_start_without_a_token(self):
        r = subprocess.run([sys.executable, str(API)], env={k: v for k, v in os.environ.items() if k != "HANDOVER_API_TOKEN"}, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(r.returncode, 0); self.assertIn("refusing", r.stderr + r.stdout)

    def test_validation(self):
        ok = {"repo": "github.com/Max-imalgutaussehend/demo", "slug": "x-1", "note": "n"}
        for patch, code in (({"slug": "Bad Slug"}, 400), ({"slug": "-x"}, 400), ({"repo": "github.com/evil/demo"}, 403),
                            ({"repo": "github.com/Max-imalgutaussehend/../etc"}, 400), ({"repo": "nonsense"}, 400),
                            ({"note": ""}, 400), ({"note": "x" * 200_000}, 413), ({"base": "a b"}, 400)):
            self.assertEqual(self.call("POST", "/start", {**ok, **patch})[0], code, patch)

    def test_start_creates_branch_note_and_runs_the_agent(self):
        note = "# Handover: Test\n## Goal\nmake it so\n"
        code, out = self.call("POST", "/start", {"repo": "github.com/Max-imalgutaussehend/demo", "slug": "demo-task", "note": note})
        self.assertEqual(code, 200, out); self.assertEqual(out["branch"], "handover/demo-task")
        self.assertEqual(git("show", "handover/demo-task:.handover/demo-task/HANDOVER.md", cwd=self.bare), note)
        self.assertIn("start", (TMP / "runner.log").read_text()); self.assertIn("handover/demo-task demo-task", (TMP / "runner.log").read_text())
        self.assertEqual(self.call("POST", "/start", {"repo": "github.com/Max-imalgutaussehend/demo", "slug": "demo-task", "note": note})[0], 409)
        self.assertEqual(git("log", "-1", "--format=%s", "main", cwd=self.bare).strip(), "init")  # main is untouched

    def test_unknown_repository(self):
        self.assertEqual(self.call("POST", "/start", {"repo": "github.com/Max-imalgutaussehend/nope", "slug": "x", "note": "n"})[0], 502)

    def test_status_result_list_stop(self):
        code, s = self.call("GET", "/status/x"); self.assertEqual((code, s["status"], s["finished"]), (200, "done", "2026-10-21T10:05:00Z"))
        self.assertEqual(s["commits"], ["abc123 handover(x): agent work and result"])
        self.assertIn("all of it", self.call("GET", "/result/x")[1]["result"])
        self.assertEqual(self.call("GET", "/list")[1]["handovers"], [{"slug": "alpha", "status": "running"}, {"slug": "beta", "status": "done"}])
        self.assertTrue(self.call("POST", "/stop/x")[1]["ok"])
        self.assertEqual(self.call("GET", "/status/BAD!")[0], 400)


if __name__ == "__main__":
    unittest.main()
