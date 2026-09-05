export function insertCoverIntoBody(raw, markdown, previousMarkdown) {
  let body = raw || "";
  // Only this plugin's marked images are removed; other article images are preserved.
  body = body.replace(/^!\[topic-cover-\d+\]\([^\r\n]+\)[ \t]*(?:\r?\n)?/gm, "");
  if (previousMarkdown) {
    body = body.split(previousMarkdown).join("");
  }
  body = body.replace(/^\s*\n/, "");
  return { raw: body ? `${markdown}\n\n${body}` : markdown, markdown };
}
