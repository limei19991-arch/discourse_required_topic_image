import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";

export default class TopicCoverPublishProgress extends Component {
  static shouldRender(args, { siteSettings }) {
    const composer = args.model;

    return (
      siteSettings.topic_cover_enabled &&
      composer?.canEditTitle &&
      !composer?.creatingPrivateMessage
    );
  }

  get isPublishing() {
    return this.args.outletArgs.model.composeState === "saving";
  }

  <template>
    {{#if this.isPublishing}}
      <div
        class="topic-cover-publish-progress"
        role="progressbar"
        aria-label={{i18n "topic_cover.publishing"}}
      >
        <div class="topic-cover-publish-progress__track">
          <div class="topic-cover-publish-progress__bar"></div>
        </div>
        <span class="topic-cover-publish-progress__label">
          {{i18n "topic_cover.publishing"}}
        </span>
      </div>
    {{/if}}
  </template>
}
