import Component from "@glimmer/component";

// Empty for overwrite upgrades: use the native editor image uploader.
export default class TopicCoverUploader extends Component {
  static shouldRender() {
    return false;
  }

  <template></template>
}
