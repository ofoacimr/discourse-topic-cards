import { render } from "@ember/test-helpers";
import { hbs } from "ember-cli-htmlbars";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import TopicActionButtons from "../../javascripts/discourse/components/topic-action-buttons";
import TopicByline from "../../javascripts/discourse/components/topic-byline";
import TopicExcerpt from "../../javascripts/discourse/components/topic-excerpt";
import TopicMetadata from "../../javascripts/discourse/components/topic-metadata";
import TopicTagsInline from "../../javascripts/discourse/components/topic-tags-inline";

// Mark imports as used (referenced in templates via hbs)
void [
  TopicExcerpt,
  TopicTagsInline,
  TopicByline,
  TopicMetadata,
  TopicActionButtons,
];

module("Topic Cards Theme Component", function (hooks) {
  setupRenderingTest(hooks);

  module("Component Rendering", function () {
    test("smoke test - component loads without error", function (assert) {
      assert.ok(true, "Topic Cards theme component initialized successfully");
    });

    test("TopicExcerpt renders with BEM classes", async function (assert) {
      this.set("topic", {
        escapedExcerpt: "This is a test excerpt",
      });

      await render(hbs`
        <TopicExcerpt @topic={{this.topic}} />
      `);

      assert.dom(".topic-card__excerpt").exists("Excerpt container exists");
      assert
        .dom(".topic-card__excerpt-text")
        .exists("Excerpt text wrapper exists");
      assert
        .dom(".topic-card__excerpt-text")
        .hasText("This is a test excerpt", "Excerpt text is rendered");
    });

    test("Tags render in byline when topic has tags", async function (assert) {
      this.set("topic", {
        creator: { username: "testuser" },
        tags: ["tag1", "tag2"],
      });

      await render(hbs`
        <TopicByline @topic={{this.topic}} />
      `);

      assert
        .dom(".topic-card__tags-inline-in-byline")
        .exists("Tags wrapper exists in byline");
      assert
        .dom(".topic-card__tags-inline-in-byline")
        .includesText("tag1", "Tag text is rendered in byline");
    });

    test("TopicByline renders author with BEM classes", async function (assert) {
      this.set("topic", {
        creator: {
          username: "testuser",
          avatar_template: "/images/avatar.png",
        },
        createdAt: new Date(),
      });

      await render(hbs`
        <TopicByline @topic={{this.topic}} />
      `);

      assert.dom(".topic-card__byline").exists("Byline container exists");
      assert.dom(".topic-card__op").exists("OP container exists");
      assert.dom(".topic-card__op .username").hasText("testuser");
    });

    test("TopicMetadata uses BEM-compliant classes", async function (assert) {
      this.set("topic", {
        views: 100,
        replyCount: 5,
        like_count: 10,
      });

      await render(hbs`
        <TopicMetadata @topic={{this.topic}} />
      `);

      assert.dom(".topic-card__metadata").exists("Metadata container exists");
      assert
        .dom(".topic-card__metadata-items")
        .exists("Metadata items container uses BEM class");
      assert
        .dom(".topic-card__metadata .right-aligned")
        .doesNotExist("Old non-BEM class is not present");
    });
  });

  module("Featured Link Behavior", function () {
    test("TopicActionButtons renders when featured link exists", async function (assert) {
      this.set("topic", {
        featuredLink: "https://example.com",
        title: "Test Topic",
        lastUnreadUrl: "/t/test-topic/123",
      });

      await render(hbs`
        <TopicActionButtons @topic={{this.topic}} />
      `);

      assert.dom(".topic-card__actions").exists("Actions container exists");
      assert
        .dom(".topic-card__details-btn")
        .exists("Details button is rendered");
      assert
        .dom(".topic-card__featured-link-btn")
        .exists("Featured link button is rendered");
      assert
        .dom(".topic-card__featured-link-btn")
        .hasAttribute("href", "https://example.com");
      assert
        .dom(".topic-card__featured-link-btn")
        .hasAttribute("target", "_blank");
      assert
        .dom(".topic-card__featured-link-btn")
        .hasAttribute("rel", "noopener noreferrer");
    });

    test("TopicActionButtons does not render when no featured link", async function (assert) {
      this.set("topic", {
        title: "Test Topic",
        lastUnreadUrl: "/t/test-topic/123",
      });

      await render(hbs`
        <TopicActionButtons @topic={{this.topic}} />
      `);

      assert
        .dom(".topic-card__actions")
        .doesNotExist(
          "Actions container does not render without featured link"
        );
    });
  });

  module("Accessibility", function () {
    test("TopicActionButtons has proper ARIA labels", async function (assert) {
      this.set("topic", {
        featuredLink: "https://example.com",
        title: "Test Topic",
        lastUnreadUrl: "/t/test-topic/123",
      });

      await render(hbs`
        <TopicActionButtons @topic={{this.topic}} />
      `);

      assert
        .dom(".topic-card__details-btn")
        .hasAttribute("aria-label", /.+/, "Details button has aria-label");
      assert
        .dom(".topic-card__featured-link-btn")
        .hasAttribute(
          "aria-label",
          /.+/,
          "Featured link button has aria-label"
        );
    });
  });
});
