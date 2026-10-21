"""GOLEM.GDE: NextGuide syntax, limits and coverage of every .golem command.

The limits are the ones NextGuide's own manual gives: node names up to 15
characters, 80 visible characters per line, 255 characters read per line,
63 for @author/@copyright/@title.
"""
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GUIDE = REPO / "src" / "guide" / "GOLEM.GDE"
DATA = REPO / "src" / "dot" / "golem" / "data.s"
LINK = re.compile(r'@\{"([^"]*)" LINK (\S+?)\}')
ATTR = re.compile(r"@\{(b|ub|i|ui|c|r|h1|h2|h3|h4)\}")


def visible(line):
    return ATTR.sub("", LINK.sub(r"\1", line)).replace("@@", "@")


class GolemGuideTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = GUIDE.read_text(encoding="ascii")
        cls.lines = cls.text.split("\n")
        cls.nodes = re.findall(r"^@node (\S+)$", cls.text, re.M)

    def test_plain_ascii_lf(self):
        self.assertNotIn("\r", self.text)
        self.assertTrue(self.text.endswith("\n"))

    def test_nodes(self):
        self.assertEqual(len(self.nodes), len(set(self.nodes)))
        self.assertIn("MAIN", self.nodes)
        self.assertEqual(self.nodes[0], "MAIN")
        for node in self.nodes:
            self.assertLessEqual(len(node), 15, node)

    def test_links_and_navigation_point_to_nodes(self):
        targets = [t for _, t in LINK.findall(self.text)]
        targets += re.findall(r"^@(?:next|prev|toc|index) (\S+)$", self.text, re.M)
        for target in targets:
            self.assertIn(target, self.nodes, target)

    def test_line_limits(self):
        for number, line in enumerate(self.lines, 1):
            self.assertLessEqual(len(line), 255, number)
            if not line.startswith("@") or line.startswith("@{"):
                self.assertLessEqual(len(visible(line)), 80, f"line {number}: {line}")
            self.assertNotRegex(ATTR.sub("", LINK.sub("", line)), r"@\{", f"line {number}")

    def test_metadata_lengths(self):
        for key in ("title", "author", "copyright"):
            value = re.search(rf"^@{key} (.*)$", self.text, re.M).group(1)
            self.assertLessEqual(len(value), 63, key)

    def test_every_usage_command_has_a_node(self):
        usage = re.search(r'msg_usage:\n((?:\s+db .*\n)+)', DATA.read_text()).group(1)
        words = re.search(r'"\.golem ([a-z|]+)"\s*\n\s*db "([a-z|]+)"', usage)
        commands = (words.group(1) + words.group(2)).split("|")
        self.assertIn("set", commands)
        self.assertIn('"Help: .guide golem"', usage)
        for command in commands:
            heading = f"@{{c}}@{{h1}}.golem {command}"
            self.assertIn(heading, self.text, command)


if __name__ == "__main__":
    unittest.main()
