// Quoted source text must remain verbatim when the Stop hook requests a rewrite.
module.exports = (context) => ({
  [context.Syntax.BlockQuote](node) {
    context.shouldIgnore(node.range);
  },
});
