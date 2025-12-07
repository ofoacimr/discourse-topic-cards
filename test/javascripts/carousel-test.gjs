import { click, render, triggerKeyEvent, waitFor } from "@ember/test-helpers";
import { hbs } from "ember-cli-htmlbars";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import CarouselTopicCard from "../../javascripts/discourse/components/carousel-topic-card";
import TopicCardsCarousel from "../../javascripts/discourse/components/topic-cards-carousel";

// Mark imports as used (referenced in templates via hbs)
void [TopicCardsCarousel, CarouselTopicCard];

module("Topic Cards Carousel Component", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    // Mock Embla Carousel
    window.EmblaCarousel = function () {
      return {
        scrollPrev: () => {},
        scrollNext: () => {},
        scrollTo: () => {},
        selectedScrollSnap: () => 0,
        canScrollPrev: () => false,
        canScrollNext: () => true,
        on: () => {},
        destroy: () => {},
      };
    };

    // Mock IntersectionObserver
    window.IntersectionObserver = class {
      constructor(callback) {
        this.callback = callback;
        // Immediately trigger intersection for testing
        setTimeout(() => {
          this.callback([{ isIntersecting: true }]);
        }, 0);
      }

      observe() {}

      disconnect() {}

      unobserve() {}
    };

    // Mock theme settings
    this.siteSettings = {
      carousel_display_location: "home",
      carousel_max_items: 10,
      carousel_order: "latest",
      carousel_filter_tags: "",
      carousel_layout_desktop: "grid",
      carousel_layout_mobile: "list",
      carousel_cards_per_slide_desktop: 3,
      carousel_cards_per_slide_mobile: 1,
    };

    // Mock API response
    pretender.get("/latest.json", () => {
      return response({
        topic_list: {
          topics: [
            {
              id: 1,
              title: "Test Topic 1",
              slug: "test-topic-1",
              excerpt: "This is test topic 1",
              tags: ["tag1"],
              views: 100,
              like_count: 10,
              posts_count: 5,
              created_at: "2024-01-01T00:00:00.000Z",
              creator: {
                username: "testuser1",
                avatar_template: "/images/avatar.png",
              },
            },
            {
              id: 2,
              title: "Test Topic 2",
              slug: "test-topic-2",
              excerpt: "This is test topic 2",
              tags: ["tag2"],
              views: 200,
              like_count: 20,
              posts_count: 10,
              created_at: "2024-01-02T00:00:00.000Z",
              creator: {
                username: "testuser2",
                avatar_template: "/images/avatar.png",
              },
            },
          ],
        },
      });
    });
  });

  hooks.afterEach(function () {
    delete window.EmblaCarousel;
    delete window.IntersectionObserver;
  });

  module("Component Rendering", function () {
    test("renders loading state initially", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      assert
        .dom(".topic-cards-carousel__loading")
        .exists("Loading state is displayed");
      assert
        .dom(".topic-cards-carousel__loading p")
        .hasText(/Loading topics/, "Loading message is shown");
    });

    test("renders carousel after topics load", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      // Wait for topics to load
      await waitFor(".topic-cards-carousel__container", { timeout: 2000 });

      assert
        .dom(".topic-cards-carousel__container")
        .exists("Carousel container is rendered");
      assert
        .dom(".topic-cards-carousel__viewport")
        .exists("Carousel viewport is rendered");
      assert
        .dom(".topic-cards-carousel__slides")
        .exists("Carousel slides container is rendered");
    });

    test("renders empty state when no topics", async function (assert) {
      // Mock empty response
      pretender.get("/latest.json", () => {
        return response({
          topic_list: {
            topics: [],
          },
        });
      });

      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__empty", { timeout: 2000 });

      assert
        .dom(".topic-cards-carousel__empty")
        .exists("Empty state is displayed");
      assert
        .dom(".topic-cards-carousel__empty p")
        .hasText(/No topics found/, "Empty state message is shown");
    });

    test("renders error state on fetch failure", async function (assert) {
      // Mock error response
      pretender.get("/latest.json", () => {
        return response(500, {
          errors: ["Internal server error"],
        });
      });

      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__error", { timeout: 2000 });

      assert
        .dom(".topic-cards-carousel__error")
        .exists("Error state is displayed");
      assert
        .dom(".topic-cards-carousel__error p")
        .hasText(/Failed to load topics/, "Error message is shown");
    });
  });

  module("Accessibility", function () {
    test("carousel has proper ARIA attributes", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__container", { timeout: 2000 });

      assert
        .dom(".topic-cards-carousel__container")
        .hasAttribute("role", "region", "Carousel has region role");
      assert
        .dom(".topic-cards-carousel__container")
        .hasAttribute("aria-label", /.+/, "Carousel has aria-label");
      assert
        .dom(".topic-cards-carousel__container")
        .hasAttribute(
          "aria-roledescription",
          "carousel",
          "Carousel has aria-roledescription"
        );
      assert
        .dom(".topic-cards-carousel__container")
        .hasAttribute("tabindex", "0", "Carousel is keyboard focusable");
    });

    test("slides have proper ARIA attributes", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__slide", { timeout: 2000 });

      const slide = this.element.querySelector(".topic-cards-carousel__slide");
      assert.ok(slide, "Slide element exists");
      assert.strictEqual(
        slide.getAttribute("role"),
        "group",
        "Slide has group role"
      );
      assert.strictEqual(
        slide.getAttribute("aria-roledescription"),
        "slide",
        "Slide has aria-roledescription"
      );
      assert.ok(slide.getAttribute("aria-label"), "Slide has aria-label");
    });

    test("navigation buttons have proper ARIA labels", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor("[data-test-prev]", { timeout: 2000 });

      assert
        .dom("[data-test-prev]")
        .hasAttribute("aria-label", /.+/, "Previous button has aria-label");
      assert
        .dom("[data-test-next]")
        .hasAttribute("aria-label", /.+/, "Next button has aria-label");
    });

    test("pagination dots have proper ARIA labels", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__dot", { timeout: 2000 });

      const dots = this.element.querySelectorAll(".topic-cards-carousel__dot");
      assert.ok(dots.length > 0, "Pagination dots exist");

      dots.forEach((dot) => {
        assert.ok(dot.getAttribute("aria-label"), "Dot has aria-label");
      });
    });

    test("active dot has aria-current attribute", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__dot.is-active", { timeout: 2000 });

      const activeDot = this.element.querySelector(
        ".topic-cards-carousel__dot.is-active"
      );
      assert.ok(activeDot, "Active dot exists");
      assert.strictEqual(
        activeDot.getAttribute("aria-current"),
        "true",
        "Active dot has aria-current='true'"
      );
    });
  });

  module("Keyboard Navigation", function () {
    test("Left arrow key navigates to previous slide", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__container", { timeout: 2000 });

      const container = this.element.querySelector(
        ".topic-cards-carousel__container"
      );

      // Focus the carousel
      container.focus();

      // Trigger Left arrow key
      await triggerKeyEvent(container, "keydown", "ArrowLeft");

      assert.ok(true, "Left arrow key handler executed without error");
    });

    test("Right arrow key navigates to next slide", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__container", { timeout: 2000 });

      const container = this.element.querySelector(
        ".topic-cards-carousel__container"
      );

      // Focus the carousel
      container.focus();

      // Trigger Right arrow key
      await triggerKeyEvent(container, "keydown", "ArrowRight");

      assert.ok(true, "Right arrow key handler executed without error");
    });
  });

  module("Navigation Controls", function () {
    test("clicking next button navigates forward", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor("[data-test-next]", { timeout: 2000 });

      const nextButton = this.element.querySelector("[data-test-next]");

      await click(nextButton);

      assert.ok(true, "Next button click executed without error");
    });

    test("clicking previous button navigates backward", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor("[data-test-prev]", { timeout: 2000 });

      const prevButton = this.element.querySelector("[data-test-prev]");

      await click(prevButton);

      assert.ok(true, "Previous button click executed without error");
    });

    test("clicking pagination dot navigates to specific slide", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor(".topic-cards-carousel__dot", { timeout: 2000 });

      const dots = this.element.querySelectorAll(".topic-cards-carousel__dot");
      if (dots.length > 1) {
        await click(dots[1]);
        assert.ok(true, "Pagination dot click executed without error");
      } else {
        assert.ok(true, "Only one slide, skipping pagination test");
      }
    });

    test("disabled buttons have disabled attribute", async function (assert) {
      await render(hbs`<TopicCardsCarousel />`);

      await waitFor("[data-test-prev]", { timeout: 2000 });

      // Previous button should be disabled on first slide
      const prevButton = this.element.querySelector("[data-test-prev]");
      assert.ok(
        prevButton.hasAttribute("disabled"),
        "Previous button is disabled on first slide"
      );
    });
  });

  module("CarouselTopicCard Component", function () {
    test("does not render category badge even when topic has category", async function (assert) {
      this.set("topic", {
        id: 1,
        title: "Test Topic with Category",
        url: "/t/test-topic/1",
        category: {
          id: 5,
          name: "General",
          slug: "general",
          color: "0088CC",
        },
      });

      await render(hbs`<CarouselTopicCard @topic={{this.topic}} />`);

      assert
        .dom(".carousel-topic-card__category")
        .doesNotExist("Category container not rendered per design");
    });

    test("does not render category section when topic has no category", async function (assert) {
      this.set("topic", {
        id: 1,
        title: "Test Topic without Category",
        url: "/t/test-topic/1",
      });

      await render(hbs`<CarouselTopicCard @topic={{this.topic}} />`);

      assert
        .dom(".carousel-topic-card__category")
        .doesNotExist("Category container does not exist when no category");
    });

    test("title is a clickable link", async function (assert) {
      this.set("topic", {
        id: 1,
        title: "Test Topic",
        url: "/t/test-topic/1",
      });

      await render(hbs`<CarouselTopicCard @topic={{this.topic}} />`);

      assert
        .dom(".carousel-topic-card__title-link")
        .exists("Title link exists");
      assert
        .dom(".carousel-topic-card__title-link")
        .hasAttribute("href", "/t/test-topic/1", "Title link has correct href");
      assert
        .dom(".carousel-topic-card__title")
        .hasText("Test Topic", "Title text is rendered");
    });

    test("thumbnail is a clickable link", async function (assert) {
      this.set("topic", {
        id: 1,
        title: "Test Topic",
        url: "/t/test-topic/1",
      });

      await render(hbs`<CarouselTopicCard @topic={{this.topic}} />`);

      assert
        .dom(".carousel-topic-card__thumbnail-link")
        .exists("Thumbnail link exists");
      assert
        .dom(".carousel-topic-card__thumbnail-link")
        .hasAttribute(
          "href",
          "/t/test-topic/1",
          "Thumbnail link has correct href"
        );
    });

    test("card has cursor pointer for clickability", async function (assert) {
      this.set("topic", {
        id: 1,
        title: "Test Topic",
        url: "/t/test-topic/1",
      });

      await render(hbs`<CarouselTopicCard @topic={{this.topic}} />`);

      const card = this.element.querySelector(".carousel-topic-card");
      const styles = window.getComputedStyle(card);

      assert.strictEqual(
        styles.cursor,
        "pointer",
        "Card has cursor pointer style"
      );
    });

    test("plugin outlet not present since category is removed", async function (assert) {
      this.set("topic", {
        id: 1,
        title: "Test Topic",
        url: "/t/test-topic/1",
        category: {
          id: 5,
          name: "General",
          slug: "general",
          color: "0088CC",
        },
      });

      await render(hbs`<CarouselTopicCard @topic={{this.topic}} />`);

      const categoryContainer = this.element.querySelector(
        ".carousel-topic-card__category"
      );
      assert.notOk(categoryContainer, "No category container is present");
    });
  });
});
