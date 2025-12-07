import discourseTags from "discourse/helpers/discourse-tags";

const TopicTagsMobile = <template>
  <td class="topic-card__tags">
    {{discourseTags @topic mode="list" tagsForUser=@tagsForUser}}
  </td>
</template>;

export default TopicTagsMobile;
