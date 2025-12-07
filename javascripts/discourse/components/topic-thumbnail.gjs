import Component from "@glimmer/component";
import { computed } from "@ember/object";
import dIcon from "discourse/helpers/d-icon";

export default class TopicThumbnail extends Component {
  responsiveRatios = [1, 1.5, 2];

  get topic() {
    return this.args.topic || this.args.outletArgs.topic;
  }

  @computed("topic.thumbnails")
  get hasThumbnail() {
    const thumbs = this.topic.thumbnails;
    if (!thumbs || !Array.isArray(thumbs)) {
      return false;
    }
    // Consider it a thumbnail only if there's at least one item with a URL
    return thumbs.some((t) => t && t.url);
  }

  @computed("topic.thumbnails", "displayWidth")
  get srcSet() {
    const srcSetArray = [];

    this.responsiveRatios.forEach((ratio) => {
      const target = ratio * this.displayWidth;
      const match = this.topic.thumbnails.find(
        (t) => t.url && t.max_width === target
      );
      if (match) {
        srcSetArray.push(`${match.url} ${ratio}x`);
      }
    });

    if (srcSetArray.length === 0) {
      srcSetArray.push(`${this.original.url} 1x`);
    }

    return srcSetArray.join(",");
  }

  @computed("topic.thumbnails")
  get original() {
    return this.topic.thumbnails[0];
  }

  get width() {
    return this.original.width;
  }

  get isLandscape() {
    return this.original.width >= this.original.height;
  }

  get height() {
    return this.original.height;
  }

  @computed("topic.thumbnails")
  get fallbackSrc() {
    const largeEnough = this.topic.thumbnails.filter((t) => {
      if (!t.url) {
        return false;
      }
      return t.max_width > this.displayWidth * this.responsiveRatios.lastObject;
    });

    if (largeEnough.lastObject) {
      return largeEnough.lastObject.url;
    }

    return this.original.url;
  }

  get url() {
    return this.topic.linked_post_number
      ? this.topic.urlForPostNumber(this.topic.linked_post_number)
      : this.topic.get("lastUnreadUrl");
  }

  get placeholderIconName() {
    const raw = settings?.thumbnail_placeholder_icon || "fa-image";
    return raw.replace?.(/^fa-/, "") || "image";
  }

  <template>
    {{#if this.hasThumbnail}}
      <td class="topic-card__thumbnail">
        <a href={{this.url}}>
          <img
            class="main-thumbnail"
            src={{this.fallbackSrc}}
            srcset={{this.srcSet}}
            width={{this.width}}
            height={{this.height}}
            loading="lazy"
          />
        </a>
      </td>
    {{/if}}
  </template>
}
