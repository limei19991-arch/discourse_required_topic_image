import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import UppyImageUploader from "discourse/components/uppy-image-uploader";
import { i18n } from "discourse-i18n";
import { insertCoverIntoBody } from "../../lib/cover-body";

export default class TopicCoverUploader extends Component {
  @tracked coverUrl;

  static shouldRender(args, { siteSettings }) {
    return siteSettings.topic_cover_enabled && args.model?.canEditTitle &&
      !args.model?.creatingPrivateMessage;
  }

  get composer() {
    return this.args.outletArgs.model;
  }

  @action
  uploadDone(upload) {
    const url = (upload.short_url || upload.url).replace(/[\s()<>]/g, (character) =>
      encodeURIComponent(character).replace(/\(/g, "%28").replace(/\)/g, "%29")
    );
    const markdown = `![topic-cover-${upload.id}](${url})`;
    const result = insertCoverIntoBody(this.composer.reply, markdown,
      this.composer.topicCoverBodyMarkdown);
    this.composer.setProperties({
      reply: result.raw,
      topicCoverBodyMarkdown: result.markdown,
    });
    this.coverUrl = upload.url;
  }

  @action
  keepCover() {}

  <template>
    <div class="topic-cover-field">
      <label class="topic-cover-field__label">
        {{i18n "topic_cover.label"}}
        <span class="topic-cover-field__required" aria-hidden="true">*</span>
      </label>
      <UppyImageUploader
        @id="topic-cover-image-uploader"
        @type="topic_cover"
        @imageUrl={{this.coverUrl}}
        @onUploadDone={{this.uploadDone}}
        @onUploadDeleted={{this.keepCover}}
        @previewSize="cover"
      />
      <div class="topic-cover-field__help">{{i18n "topic_cover.help"}}</div>
    </div>
  </template>
}
