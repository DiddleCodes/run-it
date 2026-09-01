// @nestjs/bullmq ships ESM-only ("type": "module", no CJS build), which
// ts-jest's default CommonJS transform can't parse. This is a test-runner-
// only substitute (wired via jest.moduleNameMapper in package.json) — real
// builds/runtime (`nest build`, `nest start`) still resolve the actual npm
// package. Only the handful of exports our code actually imports are
// stubbed, matching each real export's shape closely enough for a unit
// test: decorators that are no-ops (our tests instantiate the decorated
// classes directly, never through Nest's DI/BullMQ registration), and
// WorkerHost's real "throw until initialized" getter, since nothing in our
// tests touches `.worker` anyway.
function InjectQueue() {
  return function () {};
}

function Processor() {
  return function (target) {
    return target;
  };
}

function OnWorkerEvent() {
  return function () {};
}

class WorkerHost {
  get worker() {
    if (!this._worker) {
      throw new Error('"Worker" has not yet been initialized.');
    }
    return this._worker;
  }
}

module.exports = { InjectQueue, Processor, OnWorkerEvent, WorkerHost };
