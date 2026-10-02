// WorkerScript entry (ADR-0026): all snapshot parsing, mapping and searching happen on this
// thread. Logic lives in lib/service.mjs; this file only wires messages.
import * as Service from "../lib/service.mjs";

var svc = Service.createService();

WorkerScript.onMessage = function (msg) {
  var reply;
  try {
    reply = Service.handle(svc, msg);
  } catch (e) {
    reply = { type: "error", error: String(e), on: msg.type };
  }
  WorkerScript.sendMessage(reply);
};
