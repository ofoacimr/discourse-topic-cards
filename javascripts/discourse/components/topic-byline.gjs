import UserLink from "discourse/components/user-link";
import avatar from "discourse/helpers/avatar";
import formatDate from "discourse/helpers/format-date";
import discourseTags from "discourse/helpers/discourse-tags";

/**
 * TopicByline Component
 *
 * Renders the topic author (OP) with avatar and optional publish date.
 * Also renders inline tags next to OP according to rules:
 * - If publish date is enabled and topic has tags: show tags between OP and publish date, and do not show the meta separator.
 * - If publish date is enabled and topic has no tags: keep the meta separator and show publish date.
 * - If publish date is disabled: show tags next to OP if present (no meta separator/publish-date).
 */
const TopicByline = <template>
  <div class="topic-card__byline">
    <div class="topic-card__op">
      <UserLink @user={{@topic.creator}}>
        {{avatar @topic.creator imageSize="tiny"}}
        <span class="username">
          {{@topic.creator.username}}
        </span>
      </UserLink>
    </div>

    {{! Case: publish date enabled }}
    {{#if settings.show_publish_date}}
      {{#if @topic.tags}}
        <div class="topic-card__tags-inline-in-byline">
          {{discourseTags @topic mode="list"}}
        </div>
        <span class="topic-card__publish-date">
          {{formatDate @topic.createdAt format="medium-with-ago"}}
        </span>
      {{else}}
        <span class="topic-card__meta-sep" aria-hidden="true">•</span>
        <span class="topic-card__publish-date">
          {{formatDate @topic.createdAt format="medium-with-ago"}}
        </span>
      {{/if}}

      {{! Case: publish date disabled }}
    {{else}}
      {{#if @topic.tags}}
        <div class="topic-card__tags-inline-in-byline">
          {{discourseTags @topic mode="list"}}
        </div>
      {{/if}}
    {{/if}}
  </div>
</template>;

export default TopicByline;
