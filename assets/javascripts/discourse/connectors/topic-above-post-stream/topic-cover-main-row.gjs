import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";

export default class TopicCoverMainRow extends Component {
  static shouldRender(args) {
    const topic = args.model;

    return Boolean(topic?.topic_cover_url || topic?.topicCoverUrl);
  }

  get coverUrl() {
    const topic = this.args.outletArgs.model;
    return topic.topic_cover_url || topic.topicCoverUrl;
  }

  <template>
    <section class="topic-cover-main-row">
      <img
        class="topic-cover-main-row__image"
        src={{this.coverUrl}}
        alt={{i18n "topic_cover.in_post_alt"}}
      />
    </section>
  </template>
}
