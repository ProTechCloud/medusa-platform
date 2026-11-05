const { readFileSync } = require("node:fs");

// The comments are the template's prompts, so a section holding only
// them is empty, and so is one holding only an empty code fence. Inside
// a fence, a heading is not a section and a checkbox is not an item; a
// fence closes only on its own character, at its length or longer.
function sections(text) {
  const found = new Map();
  let section;
  let fence;
  for (const line of text.replace(/<!--[\s\S]*?-->/g, "").split(/\r?\n/)) {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    const wasFenced = Boolean(fence);
    if (marker && !fence) {
      fence = marker[1];
    } else if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && !marker[2].trim()) {
      fence = undefined;
    }
    const fenced = wasFenced || Boolean(fence);
    const heading = fenced ? null : line.match(/^##\s+(.+?)\s*$/);
    if (heading) {
      section = { text: "", items: [] };
      found.set(heading[1], section);
    } else if (section && !marker) {
      section.text += line;
      const item = fenced ? null : line.match(/^\s*[-*] \[( |x)\]\s*(.+?)\s*$/i);
      if (item) section.items.push({ ticked: item[1] !== " ", text: item[2] });
    }
  }
  return found;
}

const template = sections(readFileSync("base/.github/pull_request_template.md", "utf8"));
const body = sections(process.env.BODY);
const problems = [];

for (const [name, prompt] of template) {
  const section = body.get(name);
  if (!section) {
    problems.push(`"${name}" is missing`);
  } else if (!section.text.trim()) {
    problems.push(`"${name}" is empty`);
  } else {
    for (const { text } of prompt.items) {
      if (!section.items.some((item) => item.text.includes(text))) {
        problems.push(`"${name}" lost the item: ${text}`);
      }
    }
  }
}

for (const [name, section] of body) {
  for (const { ticked, text } of section.items) {
    if (!ticked && !/\bn\/a\b/i.test(text)) {
      problems.push(`"${name}" has an item neither ticked nor marked n/a: ${text}`);
    }
  }
}

for (const problem of problems) console.log(`::error::${problem}`);
process.exit(problems.length ? 1 : 0);
