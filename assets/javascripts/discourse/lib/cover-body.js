export function insertCoverIntoBody(raw, markdown, previousMarkdown) {
  const body = raw || "";
  // Replace only the exact image inserted by this composer, not arbitrary images.
  const previousIndex = previousMarkdown ? body.indexOf(previousMarkdown) : -1;
  if (previousIndex !== -1) {
    return {
      raw:
        body.slice(0, previousIndex) +
        markdown +
        body.slice(previousIndex + previousMarkdown.length),
      markdown,
    };
  }
  return { raw: body ? `${markdown}\n\n${body}` : markdown, markdown };
}
