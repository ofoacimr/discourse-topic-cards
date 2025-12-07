/** TopicTagsInline
 *
 * Intentionally kept as a no-op component: tags are rendered within the
 * byline component to avoid duplicate output. This preserves compatibility
 * for tests or callers that import the component while preventing it from
 * adding duplicate DOM nodes in the rendered topic card.
 */
const TopicTagsInline = <template></template>;

export default TopicTagsInline;
