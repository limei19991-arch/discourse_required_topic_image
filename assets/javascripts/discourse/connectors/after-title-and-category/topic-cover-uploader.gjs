import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import UppyUpload from "discourse/lib/uppy/uppy-upload";
import DButton from "discourse/ui-kit/d-button";
import DPickFilesButton from "discourse/ui-kit/d-pick-files-button";
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

  get busy() {
    return this.uploader.uploading || this.uploader.processing;
  }

  get buttonLabel() {
    return this.coverUrl ? "topic_cover.replace" : "topic_cover.upload";
  }

  uploader = new UppyUpload(getOwner(this), {
    id: "topic-cover-image-uploader",
    type: "topic_cover",
    maxFiles: 1,
    validateUploadedFilesOptions: { imagesOnly: true },
    uploadDone: (upload) => {
      if (!this.isDestroying && !this.isDestroyed) {
        this.uploadDone(upload);
      }
    },
  });

  willDestroy() {
    this.uploader.teardown();
    super.willDestroy(...arguments);
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

  <template>
    <div class="topic-cover-field">
      <DPickFilesButton
        @registerFileInput={{this.uploader.setup}}
        @fileInputDisabled={{this.busy}}
        @acceptedFormatsOverride="image/*"
        @fileInputId="topic-cover-file"
      />
      <DButton
        @action={{this.uploader.openPicker}}
        @label={{this.buttonLabel}}
        @disabled={{this.busy}}
        class="btn-default btn-small topic-cover-upload-button"
      />
      {{#if this.coverUrl}}
        <img class="topic-cover-field__thumbnail" src={{this.coverUrl}} alt={{i18n "topic_cover.in_post_alt"}} />
      {{/if}}
      <span class="topic-cover-field__help" role="status">
        {{#if this.busy}}
          {{i18n "topic_cover.uploading"}} {{this.uploader.uploadProgress}}%
        {{else}}
          {{i18n "topic_cover.help"}}
        {{/if}}
      </span>
    </div>
  </template>
}
