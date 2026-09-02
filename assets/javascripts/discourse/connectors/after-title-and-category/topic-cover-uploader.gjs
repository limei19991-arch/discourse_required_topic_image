import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import UppyImageUploader from "discourse/components/uppy-image-uploader";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const UPLOAD_ID_FIELD = "topic_cover_upload_id";

export default class TopicCoverUploader extends Component {
  @service siteSettings;

  @tracked coverUploadId;
  @tracked coverUrl;
  @tracked saving = false;

  static shouldRender(args, { siteSettings }) {
    const model = args.model;
    return (
      siteSettings.topic_cover_enabled &&
      model?.canEditTitle &&
      !model?.creatingPrivateMessage
    );
  }

  constructor() {
    super(...arguments);

    const model = this.args.outletArgs.model;
    this.coverUploadId =
      model.topicCoverUploadId || model.topic?.topic_cover_upload_id;
    this.coverUrl = model.topicCoverUploadUrl || model.topic?.topic_cover_url;

    if (this.coverUploadId) {
      this.updateComposerPayload(this.coverUploadId, this.coverUrl);
    }
  }

  get composer() {
    return this.args.outletArgs.model;
  }

  get editingExistingTopic() {
    return (
      this.composer.editingPost &&
      this.composer.post?.post_number === 1 &&
      this.composer.topic?.id
    );
  }

  updateComposerPayload(uploadId, url) {
    this.composer.setProperties({
      topicCoverUploadId: uploadId,
      topicCoverUploadUrl: url,
      topicCoverCustomFields: {
        [UPLOAD_ID_FIELD]: uploadId,
      },
    });
  }

  @action
  async uploadDone(upload) {
    const previousId = this.coverUploadId;
    const previousUrl = this.coverUrl;

    this.coverUploadId = upload.id;
    this.coverUrl = upload.url;
    this.updateComposerPayload(upload.id, upload.url);

    if (!this.editingExistingTopic) {
      return;
    }

    this.saving = true;
    try {
      const result = await ajax(`/topic-cover/${this.composer.topic.id}`, {
        type: "PUT",
        data: { upload_id: upload.id },
      });
      this.coverUploadId = result.topic_cover_upload_id;
      this.coverUrl = result.topic_cover_url;
      this.updateComposerPayload(this.coverUploadId, this.coverUrl);
    } catch (error) {
      this.coverUploadId = previousId;
      this.coverUrl = previousUrl;
      this.updateComposerPayload(previousId, previousUrl);
      popupAjaxError.call(this, error);
    } finally {
      this.saving = false;
    }
  }

  @action
  keepRequiredCover() {}

  <template>
    <div class="topic-cover-field">
      <label class="topic-cover-field__label">
        {{i18n "topic_cover.label"}}
        {{#if this.siteSettings.topic_cover_required}}
          <span class="topic-cover-field__required" aria-hidden="true">*</span>
        {{/if}}
      </label>

      <UppyImageUploader
        @id="topic-cover-image-uploader"
        @type="topic_cover"
        @imageUrl={{this.coverUrl}}
        @onUploadDone={{this.uploadDone}}
        @onUploadDeleted={{this.keepRequiredCover}}
        @disabled={{this.saving}}
        @previewSize="cover"
      />

      <div class="topic-cover-field__help">{{i18n "topic_cover.help"}}</div>
    </div>
  </template>
}
