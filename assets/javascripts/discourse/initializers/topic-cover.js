import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.34.0", (api) => {
  api.serializeOnCreate("topic_custom_fields", "topicCoverCustomFields");
  api.serializeToDraft("topicCoverUploadId");
  api.serializeToDraft("topicCoverUploadUrl");
  api.serializeToDraft("topicCoverBodyMarkdown");
});
