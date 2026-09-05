import { apiInitializer } from "discourse/lib/api";

// Native uploads are serialized in raw; no separate cover payload is needed.
export default apiInitializer("1.34.0", () => {});
