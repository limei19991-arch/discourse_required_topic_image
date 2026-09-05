import Component from "@glimmer/component";

// The cover is already visible in the post body.
export default class TopicCoverMainRow extends Component {
  static shouldRender() {
    return false;
  }

  <template></template>
}
