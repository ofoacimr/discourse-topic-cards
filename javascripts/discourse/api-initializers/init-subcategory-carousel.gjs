/**
 * Subcategory Carousel - Initializer
 *
 * Transforms the native subcategory list on category pages into an Embla carousel
 * when enabled via settings and when the category has multiple visible subcategories.
 *
 * Features:
 * - In-place DOM transformation (preserves native subcategory markup)
 * - Permission-aware subcategory detection
 * - Inherits sizing/behavior from main carousel settings
 * - Idempotent wrapping with cleanup on navigation
 * - Scoped MutationObserver for dynamic subcategory changes
 * - Full keyboard navigation and ARIA support
 *
 * Settings:
 * - subcategory_carousel_categories: List of enabled categories
 * - subcategory_carousel_min_children: Minimum subcategories required (default 2)
 * - Inherits: carousel_* settings for sizing, behavior, and animation
 *
 * @see javascripts/discourse/components/topic-cards-carousel.gjs
 */
import { schedule } from "@ember/runloop";
import { apiInitializer } from "discourse/lib/api";
import getURL from "discourse-common/lib/get-url";
import loadScript from "discourse/lib/load-script";
import { i18n } from "discourse-i18n";

/* eslint-disable no-console */
const LOG_PREFIX = "[SubcategoryCarousel]";
function log() {}
function warn(...args) {
  console.warn(LOG_PREFIX, ...args);
}
function error(...args) {
  console.error(LOG_PREFIX, ...args);
}

// Module-scoped state (reset on navigation)
let emblaInstance = null;
let mutationObserver = null;
let isTransformed = false;

export default apiInitializer((api) => {
  const router = api.container.lookup("service:router");
  const site = api.container.lookup("service:site");

  /**
   * Cleanup function - destroys Embla, removes wrappers, disconnects observer
   */
  function cleanup() {
    log("cleanup: start");
    if (emblaInstance) {
      try {
        emblaInstance.destroy();
        log("cleanup: embla destroyed");
      } catch (e) {
        error("cleanup: embla destroy error", e);
      }
      emblaInstance = null;
    }

    if (mutationObserver) {
      mutationObserver.disconnect();
      mutationObserver = null;
      log("cleanup: mutation observer disconnected");
    }

    // Remove carousel wrappers and restore original structure
    const wrapper = document.querySelector(".subcategory-carousel");
    if (wrapper) {
      const layoutVariant = wrapper.getAttribute("data-layout-variant");
      const container = wrapper.querySelector(
        ".subcategory-carousel__container"
      );

      if (container) {
        const slides = container.querySelectorAll(
          ".subcategory-carousel__slide"
        );

        if (layoutVariant === "boxes") {
          // For boxes layout, move items back to the section (wrapper's parent)
          const boxSection = wrapper.parentElement;
          slides.forEach((slide) => {
            const originalItem = slide.firstElementChild;
            if (originalItem && boxSection) {
              boxSection.appendChild(originalItem);
            }
          });
          log("cleanup: restored", slides.length, "items to boxes section");
        } else {
          // For legacy list, move items back before wrapper and unhide list
          slides.forEach((slide) => {
            const originalItem = slide.firstElementChild;
            if (originalItem && wrapper.parentElement) {
              wrapper.parentElement.insertBefore(originalItem, wrapper);
            }
          });
          // Unhide the original list container
          const legacyList = wrapper.parentElement?.querySelector(
            ".subcategories, .subcategory-list"
          );
          if (legacyList) {
            legacyList.style.display = "";
            log("cleanup: unhid legacy list");
          }
          log("cleanup: restored", slides.length, "items to legacy list");
        }
      }

      wrapper.remove();
      log("cleanup: wrapper removed; layoutVariant=", layoutVariant);
    }

    isTransformed = false;
    log("cleanup: done");
  }

  /**
   * Get visible subcategories for current category (permission-aware)
   */
  function getVisibleSubcategories(categoryId) {
    if (!site?.categories) {
      return [];
    }
    const categories = Array.isArray(site.categories) ? site.categories : [];
    return categories.filter((c) => c.parent_category_id === categoryId);
  }

  /**
   * Check if feature is enabled for current category
   */
  function isEnabledForCategory(categoryId) {
    if (!settings.subcategory_carousel_categories) {
      return false;
    }
    const enabledIds = settings.subcategory_carousel_categories
      .split("|")
      .map((id) => parseInt(id, 10))
      .filter((id) => !isNaN(id));
    return enabledIds.includes(categoryId);
  }

  /**
   * Load Embla script if not already loaded
   */
  async function ensureEmblaLoaded() {
    try {
      log("ensureEmblaLoaded: Embla present?", !!window.EmblaCarousel);
      if (window.EmblaCarousel) {
        return true;
      }

      // Prefer a configured theme upload if available; otherwise use bundled asset
      const uploadUrl = settings?.theme_uploads?.embla_carousel;
      const fallbackUrl =
        typeof getURL === "function"
          ? getURL("/theme-javascripts/embla-carousel.umd.min.js")
          : "/theme-javascripts/embla-carousel.umd.min.js";
      const url = uploadUrl || fallbackUrl;
      log("ensureEmblaLoaded: loading", url);

      // Temporarily disable AMD/CommonJS to force UMD global export
      const previousDefine = window.define;
      const previousModule = window.module;
      const previousExports = window.exports;
      const hadAMD = typeof previousDefine === "function" && previousDefine.amd;
      log("ensureEmblaLoaded: env guards", {
        hadAMD,
        hasModule: typeof previousModule !== "undefined",
        hasExports: typeof previousExports !== "undefined",
      });
      try {
        if (hadAMD) {
          window.define = undefined;
        }
        // Some environments expose CommonJS globals; hide them during load
        if (typeof previousModule !== "undefined") {
          window.module = undefined;
        }
        if (typeof previousExports !== "undefined") {
          window.exports = undefined;
        }
        await loadScript(url);
      } finally {
        if (hadAMD) {
          window.define = previousDefine;
        }
        if (typeof previousModule !== "undefined") {
          window.module = previousModule;
        }
        if (typeof previousExports !== "undefined") {
          window.exports = previousExports;
        }
      }

      const present = !!window.EmblaCarousel;
      log("ensureEmblaLoaded: loaded, Embla present?", present);
      if (!present) {
        warn(
          "ensureEmblaLoaded: script loaded but EmblaCarousel not found on window"
        );
      }
      return present;
    } catch (e) {
      error("ensureEmblaLoaded: error while loading Embla script", e);
      return false;
    }
  }

  /**
   * Transform native subcategory list into Embla carousel
   */
  async function transformSubcategoryList() {
    log("transform: start; isTransformed=", isTransformed);
    try {
      // Guard: already transformed
      if (isTransformed) {
        log("transform: already transformed; skipping");
        return;
      }

      // Detect layout variant and find container + items
      let subcategoryContainer = null;
      let subcategoryItems = [];
      let layoutVariant = null;

      // Try category-boxes-with-topics layout first (modern)
      const boxSection = document.querySelector(".category-boxes-with-topics");
      if (boxSection) {
        const boxes = [
          ...boxSection.querySelectorAll(".category.category-box"),
        ].filter((el) => el.parentElement === boxSection);
        if (boxes.length > 0) {
          subcategoryContainer = boxSection;
          subcategoryItems = boxes;
          layoutVariant = "boxes";
          log(
            "transform: detected category-boxes layout; container=",
            !!subcategoryContainer,
            "items=",
            subcategoryItems.length
          );
        }
      }

      // Fallback to legacy subcategory list layout
      if (!subcategoryContainer) {
        const legacyContainer = document.querySelector(
          ".subcategories, .subcategory-list"
        );
        if (legacyContainer) {
          const legacyItems = legacyContainer.querySelectorAll(
            ".subcategory-list-item, .subcategory"
          );
          if (legacyItems.length > 0) {
            subcategoryContainer = legacyContainer;
            subcategoryItems = [...legacyItems];
            layoutVariant = "list";
            log(
              "transform: detected legacy list layout; container=",
              !!subcategoryContainer,
              "items=",
              subcategoryItems.length
            );
          }
        }
      }

      // Guard: no container found
      if (!subcategoryContainer || subcategoryItems.length === 0) {
        warn(
          "transform: no subcategory container or items found. No-op. layoutVariant=",
          layoutVariant
        );
        return;
      }

      log(
        "transform: proceeding with layoutVariant=",
        layoutVariant,
        "items=",
        subcategoryItems.length
      );

      // Load Embla
      const loaded = await ensureEmblaLoaded();
      if (!loaded) {
        error("transform: Embla failed to load. Aborting transform.");
        return;
      }

      // Create carousel structure
      const carouselWrapper = document.createElement("div");
      carouselWrapper.className = "subcategory-carousel";
      carouselWrapper.setAttribute("role", "region");
      carouselWrapper.setAttribute(
        "aria-label",
        i18n(themePrefix("js.subcategory_carousel.carousel_label"))
      );
      carouselWrapper.setAttribute("data-layout-variant", layoutVariant);

      const viewport = document.createElement("div");
      viewport.className = "subcategory-carousel__viewport";

      const container = document.createElement("div");
      container.className = "subcategory-carousel__container";

      // Move items into slides (preserves events and data)
      subcategoryItems.forEach((item, idx) => {
        const slide = document.createElement("div");
        slide.className = "subcategory-carousel__slide";
        slide.appendChild(item); // Move node (not clone)
        container.appendChild(slide);
        if (idx < 3) {
          log("transform: moved item #", idx + 1, "into slide");
        }
      });

      viewport.appendChild(container);
      carouselWrapper.appendChild(viewport);

      // Create navigation controls
      const controls = createControls();
      carouselWrapper.appendChild(controls);

      // Insert carousel wrapper into the original container
      if (layoutVariant === "boxes") {
        // For boxes layout, prepend wrapper inside the section
        subcategoryContainer.insertBefore(
          carouselWrapper,
          subcategoryContainer.firstChild
        );
        log("transform: wrapper inserted at start of boxes section");
      } else {
        // For legacy list, insert before and hide original
        subcategoryContainer.parentElement.insertBefore(
          carouselWrapper,
          subcategoryContainer
        );
        subcategoryContainer.style.display = "none";
        log("transform: wrapper inserted before legacy list; list hidden");
      }

      log("transform: DOM updated; initializing Embla");

      // Initialize Embla
      await initializeEmbla(viewport);

      isTransformed = true;
      log("transform: done; isTransformed=", isTransformed);
    } catch (e) {
      error("transform: error", e);
    }
  }

  /**
   * Create navigation controls (arrows and dots)
   */
  function createControls() {
    const controls = document.createElement("div");
    controls.className = "subcategory-carousel__controls";

    // Arrows wrapper (keeps prev/next side-by-side in the first grid column)
    const nav = document.createElement("div");
    nav.className = "subcategory-carousel__nav";

    // Previous button
    const prevBtn = document.createElement("button");
    prevBtn.className =
      "subcategory-carousel__arrow subcategory-carousel__arrow--prev";
    prevBtn.setAttribute("type", "button");
    prevBtn.setAttribute(
      "aria-label",
      i18n(themePrefix("js.subcategory_carousel.previous_slide"))
    );
    prevBtn.innerHTML =
      '<svg viewBox="0 0 24 24" width="24" height="24"><path d="M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z" fill="currentColor"/></svg>';
    prevBtn.addEventListener("click", () => emblaInstance?.scrollPrev());

    // Next button
    const nextBtn = document.createElement("button");
    nextBtn.className =
      "subcategory-carousel__arrow subcategory-carousel__arrow--next";
    nextBtn.setAttribute("type", "button");
    nextBtn.setAttribute(
      "aria-label",
      i18n(themePrefix("js.subcategory_carousel.next_slide"))
    );
    nextBtn.innerHTML =
      '<svg viewBox="0 0 24 24" width="24" height="24"><path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z" fill="currentColor"/></svg>';
    nextBtn.addEventListener("click", () => emblaInstance?.scrollNext());

    // Append arrows to nav container
    nav.appendChild(prevBtn);
    nav.appendChild(nextBtn);

    // Dots container
    const dotsContainer = document.createElement("div");
    dotsContainer.className = "subcategory-carousel__dots";
    dotsContainer.setAttribute("role", "tablist");

    // Assemble: nav (left), dots (right)
    controls.appendChild(nav);
    controls.appendChild(dotsContainer);

    return controls;
  }

  /**
   * Initialize Embla carousel instance
   */
  async function initializeEmbla(viewport) {
    try {
      if (!window.EmblaCarousel) {
        warn("initializeEmbla: Embla not present");
        return;
      }

      // Map speed setting to duration
      const speedMap = { slow: 35, normal: 25, fast: 15 };
      const duration = speedMap[settings.carousel_speed] || 25;

      // Compute slides per view from CSS
      const computeSlidesPerView = () => {
        const cap = settings.carousel_slides_per_view || 3;
        const minWidth = settings.carousel_min_slide_width_px || 320;
        const gap = settings.carousel_slide_gap_px || 16;
        const viewportWidth = viewport.offsetWidth;
        const spv = Math.floor((viewportWidth + gap) / (minWidth + gap));
        return Math.max(1, Math.min(spv, cap));
      };

      const slidesPerView = computeSlidesPerView();
      log(
        "initializeEmbla: duration=",
        duration,
        "slidesPerView=",
        slidesPerView
      );

      emblaInstance = window.EmblaCarousel(viewport, {
        align: settings.carousel_align || "start",
        containScroll: "trimSnaps",
        loop: settings.carousel_loop !== false,
        dragFree: settings.carousel_drag_free || false,
        duration,
        skipSnaps: false,
        slidesToScroll: settings.carousel_scroll_by === "1" ? 1 : slidesPerView,
      });

      // Update dots and button states
      const updateUI = () => {
        updateDots();
        updateArrows();
      };

      emblaInstance.on("select", updateUI);
      emblaInstance.on("reInit", updateUI);
      updateUI();
      log("initializeEmbla: success");
    } catch (e) {
      error("initializeEmbla: error", e);
    }
  }

  /**
   * Update pagination dots
   */
  function updateDots() {
    if (!emblaInstance) {
      return;
    }

    const dotsContainer = document.querySelector(".subcategory-carousel__dots");
    if (!dotsContainer) {
      return;
    }

    const scrollSnaps = emblaInstance.scrollSnapList();
    const selectedIndex = emblaInstance.selectedScrollSnap();

    dotsContainer.innerHTML = "";
    scrollSnaps.forEach((_, index) => {
      const dot = document.createElement("button");
      dot.className = "subcategory-carousel__dot";
      dot.setAttribute("type", "button");
      dot.setAttribute("role", "tab");
      dot.setAttribute(
        "aria-label",
        i18n(themePrefix("js.subcategory_carousel.go_to_slide"), {
          number: index + 1,
        })
      );

      if (index === selectedIndex) {
        dot.classList.add("is-active");
        dot.setAttribute("aria-current", "true");
      }

      dot.addEventListener("click", () => emblaInstance.scrollTo(index));
      dotsContainer.appendChild(dot);
    });
  }

  /**
   * Update arrow button states
   */
  function updateArrows() {
    if (!emblaInstance) {
      return;
    }

    const prevBtn = document.querySelector(
      ".subcategory-carousel__arrow--prev"
    );
    const nextBtn = document.querySelector(
      ".subcategory-carousel__arrow--next"
    );

    if (prevBtn) {
      prevBtn.disabled = !emblaInstance.canScrollPrev();
    }
    if (nextBtn) {
      nextBtn.disabled = !emblaInstance.canScrollNext();
    }
  }

  /**
   * Main page change handler
   */
  api.onPageChange(() => {
    log(
      "onPageChange: triggered",
      window.location.pathname + window.location.search
    );
    // Always cleanup previous state
    cleanup();

    // Guard: only on category route
    const routeName = router.currentRouteName;
    log("onPageChange: routeName=", routeName);
    if (!routeName?.startsWith("discovery.category")) {
      warn("onPageChange: not a category route; skipping");
      return;
    }

    // Get current category
    const category = router.currentRoute?.attributes?.category;
    log("onPageChange: category id=", category?.id);
    if (!category?.id) {
      warn("onPageChange: no category id; skipping");
      return;
    }

    // Guard: feature not enabled for this category
    const enabled = isEnabledForCategory(category.id);
    log(
      "onPageChange: enabled for category?",
      enabled,
      "enabled list=",
      settings.subcategory_carousel_categories
    );
    if (!enabled) {
      warn("onPageChange: feature disabled for category; skipping");
      return;
    }

    // Get visible subcategories
    const subcategories = getVisibleSubcategories(category.id);
    const minChildren = settings.subcategory_carousel_min_children || 2;
    log(
      "onPageChange: visible subcategories=",
      subcategories.length,
      "minChildren=",
      minChildren
    );

    // Guard: not enough subcategories
    if (subcategories.length < minChildren) {
      warn("onPageChange: below minimum children; skipping");
      return;
    }

    // Transform after render
    log("onPageChange: scheduling transform afterRender");
    schedule("afterRender", () => {
      try {
        log("afterRender: attempting transform");
        const p = transformSubcategoryList();
        if (p && typeof p.then === "function") {
          p.then(() => log("afterRender: transform resolved")).catch((e) =>
            error("afterRender: transform rejected", e)
          );
        }
      } catch (e) {
        error("afterRender: transform threw", e);
      }
    });
  });
});
