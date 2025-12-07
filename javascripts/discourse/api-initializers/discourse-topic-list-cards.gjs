/**
 * Discourse Topic List Cards - Main Initializer
 *
 * Transforms standard Discourse topic lists into card-based layouts (list or grid style).
 * Supports per-category configuration with independent mobile/desktop settings.
 *
 * Key Features:
 * - Per-category card style configuration (list/grid/disabled) for desktop and mobile independently
 * - Custom click behavior for card navigation
 * - BEM-based CSS architecture
 * - Glimmer component-based rendering
 *
 * Component Rendering Order (via topic-list-main-link-bottom outlet):
 * 1. TopicTagsInline - Category and tags
 * 2. TopicExcerpt - Topic excerpt text
 * 3. TopicByline - Author and publish date
 * 4. TopicActionButtons - Details and featured link buttons
 * 5. TopicMetadata - Views, likes, replies, activity
 *
 * CSS Classes Applied:
 * - .topic-cards-list (list container)
 * - .topic-cards-list--list or .topic-cards-list--grid (layout variant)
 * - .topic-card (individual card)
 * - .topic-card--list or .topic-card--grid (card variant)
 */
import Component from "@glimmer/component";
import { schedule } from "@ember/runloop";
import { apiInitializer } from "discourse/lib/api";
import { wantsNewWindow } from "discourse/lib/intercept-click";
import TopicActionButtons from "../components/topic-action-buttons";
import TopicByline from "../components/topic-byline";
import TopicExcerpt from "../components/topic-excerpt";
import TopicMetadata from "../components/topic-metadata";
import TopicThumbnail from "../components/topic-thumbnail";

// Module-scoped state for effective category sets (view-only, cleared on page change)
let effectiveCategorySets = null;

export default apiInitializer((api) => {
  const site = api.container.lookup("service:site");
  const router = api.container.lookup("service:router");

  /**
   * Parses a pipe-delimited category list setting into a Set of numeric IDs.
   * @param {string} settingValue - Pipe-delimited category IDs (e.g., "1|5|12")
   * @returns {Set<number>} Set of category IDs
   */
  function parseCategoryList(settingValue) {
    return new Set(
      (settingValue || "")
        .split("|")
        .filter(Boolean)
        .map((s) => Number(s))
    );
  }

  /**
   * Builds an adjacency map of parent category ID -> array of child categories.
   * @param {Array} categories - Array of category objects from the store
   * @returns {Map<number, Array>} Map of parent ID to child categories
   */
  function buildCategoryAdjacencyMap(categories) {
    const childrenByParent = new Map();

    categories.forEach((cat) => {
      const parentId = cat.parent_category_id;
      if (parentId !== undefined && parentId !== null) {
        if (!childrenByParent.has(parentId)) {
          childrenByParent.set(parentId, []);
        }
        childrenByParent.get(parentId).push(cat);
      }
    });

    return childrenByParent;
  }

  /**
   * Recursively computes all descendant category IDs for a given parent category.
   * Uses depth-first search to traverse the category tree.
   * @param {number} parentId - Parent category ID
   * @param {Map} childrenByParent - Adjacency map from buildCategoryAdjacencyMap
   * @returns {Set<number>} Set of all descendant category IDs (excluding the parent itself)
   */
  function descendantsOf(parentId, childrenByParent) {
    const descendants = new Set();
    const stack = [parentId];

    while (stack.length > 0) {
      const currentId = stack.pop();
      const children = childrenByParent.get(currentId) || [];

      children.forEach((child) => {
        if (!descendants.has(child.id)) {
          descendants.add(child.id);
          stack.push(child.id);
        }
      });
    }

    return descendants;
  }

  /**
   * Computes effective category sets with subcategory inheritance applied.
   * Implements conflict resolution: Explicit > Inherited; Grid > List for ties.
   * @returns {Object} Object with desktop and mobile effective sets
   */
  function computeEffectiveCategorySets() {
    // Parse base category sets from settings
    const desktopList = parseCategoryList(settings.list_view_categories);
    const desktopGrid = parseCategoryList(settings.grid_view_categories);
    const mobileList = parseCategoryList(settings.mobile_list_view_categories);
    const mobileGrid = parseCategoryList(settings.mobile_grid_view_categories);

    // If inheritance is disabled, return base sets
    if (!settings.inherit_layout_to_subcategories) {
      return {
        desktop: { list: desktopList, grid: desktopGrid },
        mobile: { list: mobileList, grid: mobileGrid },
      };
    }

    // Get all categories and build adjacency map
    // Use site.categories (preloaded, user-permission-aware) instead of store.peekAll
    const categories = Array.isArray(site.categories) ? site.categories : [];

    // Guard: if no categories available, fall back to base sets (no inheritance)
    if (!categories.length) {
      return {
        desktop: { list: desktopList, grid: desktopGrid },
        mobile: { list: mobileList, grid: mobileGrid },
      };
    }

    const childrenByParent = buildCategoryAdjacencyMap(categories);

    // Helper to expand a base set with descendants
    function expandWithDescendants(baseSet) {
      const expanded = new Set(baseSet);
      baseSet.forEach((parentId) => {
        const descendants = descendantsOf(parentId, childrenByParent);
        descendants.forEach((id) => expanded.add(id));
      });
      return expanded;
    }

    // Expand all base sets with descendants
    const desktopListExpanded = expandWithDescendants(desktopList);
    const desktopGridExpanded = expandWithDescendants(desktopGrid);
    const mobileListExpanded = expandWithDescendants(mobileList);
    const mobileGridExpanded = expandWithDescendants(mobileGrid);

    // Apply conflict resolution for desktop
    const desktopListFinal = new Set();
    const desktopGridFinal = new Set();

    desktopListExpanded.forEach((id) => {
      const explicitList = desktopList.has(id);
      const explicitGrid = desktopGrid.has(id);
      const inheritedList = !explicitList && desktopListExpanded.has(id);
      const inheritedGrid = !explicitGrid && desktopGridExpanded.has(id);

      // Explicit takes precedence
      if (explicitList) {
        desktopListFinal.add(id);
      } else if (explicitGrid) {
        desktopGridFinal.add(id);
      } else if (inheritedList && inheritedGrid) {
        // Both inherited: grid wins
        desktopGridFinal.add(id);
      } else if (inheritedList) {
        desktopListFinal.add(id);
      }
    });

    desktopGridExpanded.forEach((id) => {
      if (!desktopListFinal.has(id) && !desktopGridFinal.has(id)) {
        desktopGridFinal.add(id);
      }
    });

    // Apply conflict resolution for mobile
    const mobileListFinal = new Set();
    const mobileGridFinal = new Set();

    mobileListExpanded.forEach((id) => {
      const explicitList = mobileList.has(id);
      const explicitGrid = mobileGrid.has(id);
      const inheritedList = !explicitList && mobileListExpanded.has(id);
      const inheritedGrid = !explicitGrid && mobileGridExpanded.has(id);

      // Explicit takes precedence
      if (explicitList) {
        mobileListFinal.add(id);
      } else if (explicitGrid) {
        mobileGridFinal.add(id);
      } else if (inheritedList && inheritedGrid) {
        // Both inherited: grid wins
        mobileGridFinal.add(id);
      } else if (inheritedList) {
        mobileListFinal.add(id);
      }
    });

    mobileGridExpanded.forEach((id) => {
      if (!mobileListFinal.has(id) && !mobileGridFinal.has(id)) {
        mobileGridFinal.add(id);
      }
    });

    return {
      desktop: { list: desktopListFinal, grid: desktopGridFinal },
      mobile: { list: mobileListFinal, grid: mobileGridFinal },
    };
  }

  /**
   * Determines the card style for the current category and viewport.
   * Returns "list", "grid", or null (no cards).
   *
   * Logic:
   * 1. Compute effective category sets (with inheritance if enabled)
   * 2. If both settings for the platform are empty -> null (cards disabled)
   * 3. If category is in both list and grid settings -> "list" (list takes precedence)
   * 4. If category is in list settings -> "list"
   * 5. If category is in grid settings -> "grid"
   * 6. Otherwise -> null (category not assigned, cards disabled)
   */
  function cardStyleFor({ categoryId, isMobile }) {
    // Compute effective sets if not cached
    if (!effectiveCategorySets) {
      try {
        effectiveCategorySets = computeEffectiveCategorySets();
      } catch (error) {
        // Fall back to base sets if computation fails (prevents error loops)
        console.warn(
          "[Topic Cards] Failed to compute effective category sets:",
          error
        );
        effectiveCategorySets = {
          desktop: {
            list: parseCategoryList(settings.list_view_categories),
            grid: parseCategoryList(settings.grid_view_categories),
          },
          mobile: {
            list: parseCategoryList(settings.mobile_list_view_categories),
            grid: parseCategoryList(settings.mobile_grid_view_categories),
          },
        };
      }
    }

    const platform = isMobile ? "mobile" : "desktop";
    const listCategoryIds = effectiveCategorySets[platform].list;
    const gridCategoryIds = effectiveCategorySets[platform].grid;

    // If both settings are empty for this platform, cards are disabled
    if (listCategoryIds.size === 0 && gridCategoryIds.size === 0) {
      return null;
    }

    // If not in a category context, don't show cards
    if (categoryId === undefined) {
      return null;
    }

    const inList = listCategoryIds.has(categoryId);
    const inGrid = gridCategoryIds.has(categoryId);

    // List takes precedence over grid when category is in both
    if (inList && inGrid) {
      return "list";
    }

    if (inList) {
      return "list";
    }

    if (inGrid) {
      return "grid";
    }

    // Category not assigned to either setting
    return null;
  }

  function getCardStyle() {
    const currentCat = router.currentRoute?.attributes?.category?.id;
    return cardStyleFor({
      categoryId: currentCat,
      isMobile: site.mobileView,
    });
  }

  function enableCards() {
    return getCardStyle() !== null;
  }

  api.renderInOutlet(
    "topic-list-main-link-bottom",
    class extends Component {
      static shouldRender(args, context) {
        return (
          context.siteSettings.glimmer_topic_list_mode !== "disabled" &&
          enableCards()
        );
      }

      <template>
        <TopicExcerpt @topic={{@outletArgs.topic}} />
        <TopicByline @topic={{@outletArgs.topic}} />
        <TopicActionButtons @topic={{@outletArgs.topic}} />
        <TopicMetadata @topic={{@outletArgs.topic}} />
      </template>
    }
  );

  api.registerValueTransformer(
    "topic-list-class",
    ({ value: additionalClasses }) => {
      const cardStyle = getCardStyle();
      if (cardStyle) {
        additionalClasses.push("topic-cards-list");
        additionalClasses.push(`topic-cards-list--${cardStyle}`);
      }
      return additionalClasses;
    }
  );

  api.registerValueTransformer(
    "topic-list-item-class",
    ({ value: additionalClasses }) => {
      const cardStyle = getCardStyle();
      if (cardStyle) {
        const itemClasses = ["topic-card", `topic-card--${cardStyle}`];

        // Add layout-specific max-dimension classes
        if (cardStyle === "list" && settings.set_card_max_height) {
          itemClasses.push("has-max-height");
        }
        if (
          cardStyle === "grid" &&
          settings.set_card_grid_height &&
          !site.mobileView
        ) {
          itemClasses.push("has-grid-height");
        }

        return [...additionalClasses, ...itemClasses];
      } else {
        return additionalClasses;
      }
    }
  );

  api.registerValueTransformer("topic-list-item-mobile-layout", ({ value }) => {
    if (enableCards()) {
      return false;
    }
    return value;
  });

  api.registerValueTransformer("topic-list-columns", ({ value: columns }) => {
    if (enableCards()) {
      columns.add("thumbnail", { item: TopicThumbnail }, { before: "topic" });
      // Tags are now rendered inline within the main content area
    }
    return columns;
  });

  api.registerBehaviorTransformer(
    "topic-list-item-click",
    ({ context, next }) => {
      if (enableCards()) {
        const targetElement = context.event.target;
        const topic = context.topic;

        if (
          targetElement.closest(
            "a[href], button, input, textarea, select, label[for]"
          )
        ) {
          return next();
        }

        const clickTargets = [
          "topic-list-data",
          "link-bottom-line",
          "topic-list-item",
          "topic-card__excerpt",
          "topic-card__excerpt-text",
          "topic-card__metadata",
          "topic-card__likes",
          "topic-card__byline",
          "topic-card__op",
        ];

        if (site.mobileView) {
          clickTargets.push("topic-item-metadata");
        }

        if (clickTargets.some((t) => targetElement.closest(`.${t}`))) {
          if (wantsNewWindow(context.event)) {
            return true;
          }
          return context.navigateToTopic(topic, topic.lastUnreadUrl);
        }
      }

      next();
    }
  );

  // DOM reordering: Move .topic-post-badges before .title to prevent overlap with .topic-statuses
  // This is SPA-safe and scoped to card layouts only
  let observer = null;

  function reorderBadgesAndStatuses() {
    const topicCards = document.querySelectorAll(
      ".topic-cards-list .topic-list-item, .topic-cards-list .topic-card"
    );

    topicCards.forEach((card) => {
      const linkTopLine = card.querySelector(".link-top-line");
      if (!linkTopLine) {
        return;
      }

      const badges = linkTopLine.querySelector(".topic-post-badges");
      const title = linkTopLine.querySelector(".title");

      // Only reorder if both elements exist and badges is not already before title
      if (badges && title && badges.nextElementSibling !== title) {
        // Move badges to be the first child of link-top-line
        linkTopLine.insertBefore(badges, linkTopLine.firstChild);
      }
    });
  }

  function setupObserver() {
    const containers = document.querySelectorAll(
      ".topic-cards-list .topic-list-body"
    );
    if (!containers.length) {
      return;
    }

    observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType !== 1) {
            return;
          }
          if (
            node.classList?.contains("topic-list-item") ||
            node.classList?.contains("topic-card")
          ) {
            const linkTopLine = node.querySelector(".link-top-line");
            if (!linkTopLine) {
              return;
            }

            const badges = linkTopLine.querySelector(".topic-post-badges");
            const title = linkTopLine.querySelector(".title");

            if (badges && title && badges.nextElementSibling !== title) {
              linkTopLine.insertBefore(badges, linkTopLine.firstChild);
            }
          }
        });
      });
    });

    containers.forEach((container) => {
      observer.observe(container, { childList: true, subtree: true });
    });
  }

  api.onPageChange(() => {
    // Clear cached effective category sets (view-only state)
    effectiveCategorySets = null;

    // Disconnect previous observer
    if (observer) {
      observer.disconnect();
      observer = null;
    }

    // Only process if cards are enabled
    if (!enableCards()) {
      return;
    }

    // Use schedule to ensure DOM is ready
    schedule("afterRender", () => {
      reorderBadgesAndStatuses();
      setupObserver();
    });
  });
});
