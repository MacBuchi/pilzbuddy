// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      AC: Function.prototype.call.bind(DataView.prototype.setInt16),
      AD: x0 => x0.height,
      AE: x0 => x0.languages,
      AF: x0 => x0.deltaX,
      AG: x0 => x0.first(),
      AH: (x0,x1) => { x0.scrollTop = x1 },
      AI: x0 => x0.offsetWidth,
      AJ: x0 => new Date(x0),
      AK: x0 => x0.cancel(),
      AL: x0 => x0.type,
      AM: (x0,x1) => new OffscreenCanvas(x0,x1),
      AN: (x0,x1) => { x0.rel = x1 },
      AO: x0 => x0.children,
      AP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      AQ: x0 => x0.code,
      AR: (x0,x1) => globalThis.firebase_messaging.onMessage(x0,x1),
      B: s => printToConsole(s),
      BB: b => !!b,
      BC: Function.prototype.call.bind(DataView.prototype.setUint16),
      BD: x0 => x0.width,
      BE: (x0,x1) => x0.observe(x1),
      BF: x0 => x0.wheelDeltaY,
      BG: x0 => x0.next(),
      BH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      BI: x0 => x0.stopPropagation(),
      BJ: (o, p, v) => o[p] = v,
      BK: x0 => x0.body,
      BL: x0 => x0.response,
      BM: x0 => x0.allocationSize(),
      BN: x0 => globalThis.URL.revokeObjectURL(x0),
      BO: x0 => x0.body,
      BP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      BQ: x0 => x0.speed,
      BR: x0 => globalThis.firebase_messaging.getMessaging(x0),
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      CC: Function.prototype.call.bind(DataView.prototype.setUint8),
      CD: x0 => x0.screen,
      CE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      CF: x0 => x0.wheelDeltaX,
      CG: x0 => x0.current(),
      CH: (x0,x1) => { x0.value = x1 },
      CI: x0 => x0.disabled,
      CJ: x0 => x0.name,
      CK: x0 => x0.headers,
      CL: (x0,x1) => { x0.responseType = x1 },
      CM: (x0,x1) => x0.copyTo(x1),
      CN: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      CO: (x0,x1) => { x0.download = x1 },
      CP: x0 => x0.originalEvent,
      CQ: x0 => x0.heading,
      CR: x0 => globalThis.firebase_core.getApp(x0),
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: (x0,x1) => x0.focus(x1),
      DC: Function.prototype.call.bind(DataView.prototype.setInt8),
      DD: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      DE: x0 => new ResizeObserver(x0),
      DF: x0 => x0.key,
      DG: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      DH: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      DI: (x0,x1) => { x0.min = x1 },
      DJ: x0 => x0.result,
      DK: x0 => x0.signal,
      DL: x0 => x0.vendor,
      DM: (x0,x1) => { x0.height = x1 },
      DN: (x0,x1,x2) => x0.once(x1,x2),
      DO: (x0,x1) => { x0.display = x1 },
      DP: x0 => x0.point,
      DQ: x0 => x0.accuracy,
      DR: () => globalThis.firebase_core.getApp(),
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: () => ({}),
      EC: Function.prototype.call.bind(DataView.prototype.getInt8),
      ED: x0 => x0.tabIndex,
      EE: (x0,x1) => x0.getPropertyValue(x1),
      EF: x0 => x0.identifier,
      EG: x0 => x0.v8BreakIterator,
      EH: (x0,x1) => { x0.value = x1 },
      EI: (x0,x1) => { x0.max = x1 },
      EJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      EK: o => o.byteLength,
      EL: (x0,x1) => x0.delete(x1),
      EM: (x0,x1) => { x0.width = x1 },
      EN: (x0,x1) => x0.setStyle(x1),
      EO: (x0,x1) => { x0.href = x1 },
      EP: x0 => x0.lngLat,
      EQ: x0 => x0.altitudeAccuracy,
      ER: x0 => x0.measurementId,
      F: () => new Error().stack,
      FB: (o, p, v) => o[p] = v,
      FC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      FD: (x0,x1) => x0.contains(x1),
      FE: x0 => globalThis.parseFloat(x0),
      FF: x0 => x0.touches,
      FG: () => globalThis.Intl,
      FH: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      FI: (x0,x1) => { x0.disabled = x1 },
      FJ: (x0,x1) => { x0.onerror = x1 },
      FK: x0 => x0.naturalHeight,
      FL: Function.prototype.call.bind(DataView.prototype.getBigUint64),
      FM: (x0,x1) => x0.toDataURL(x1),
      FN: (x0,x1) => x0.querySelectorAll(x1),
      FO: (x0,x1) => ({files: x0,text: x1}),
      FP: x0 => x0.getContainer(),
      FQ: x0 => x0.altitude,
      FR: x0 => x0.appId,
      G: s => JSON.stringify(s),
      GB: () => [],
      GC: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      GD: x0 => x0.activeElement,
      GE: (x0,x1) => x0.getComputedStyle(x1),
      GF: x0 => x0.pressure,
      GG: (x0,x1) => x0.segment(x1),
      GH: x0 => x0.value,
      GI: (x0,x1) => { x0.scrollLeft = x1 },
      GJ: x0 => x0.error,
      GK: x0 => x0.naturalWidth,
      GL: x0 => x0.clear(),
      GM: (x0,x1,x2,x3) => x0.drawImage(x1,x2,x3),
      GN: (x0,x1) => x0.item(x1),
      GO: x0 => ({files: x0}),
      GP: x0 => x0.getCanvas(),
      GQ: x0 => x0.timestamp,
      GR: x0 => x0.messagingSenderId,
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: (a, i) => a.push(i),
      HC: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      HD: x0 => x0.parentNode,
      HE: x0 => x0.documentElement,
      HF: x0 => x0.tiltY,
      HG: x0 => x0.index,
      HH: x0 => x0.selectionDirection,
      HI: (x0,x1) => { x0.spellcheck = x1 },
      HJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      HK: (x0,x1) => x0.createElement(x1),
      HL: x0 => globalThis.URL.createObjectURL(x0),
      HM: (x0,x1) => x0.getContext(x1),
      HN: (x0,x1) => { x0.pointerEvents = x1 },
      HO: x0 => ({text: x0}),
      HP: x0 => x0.resize(),
      HQ: x0 => x0.longitude,
      HR: x0 => x0.storageBucket,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: x0 => new Int8Array(x0),
      IC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      ID: x0 => x0.tagName,
      IE: x0 => x0.computedStyleMap(),
      IF: x0 => x0.tiltX,
      IG: x0 => x0.next(),
      IH: x0 => x0.selectionStart,
      II: (x0,x1) => { x0.disabled = x1 },
      IJ: (x0,x1) => { x0.onsuccess = x1 },
      IK: (x0,x1) => { x0.pointerEvents = x1 },
      IL: x0 => ({type: x0}),
      IM: x0 => x0.format,
      IN: x0 => x0.style,
      IO: () => ({}),
      IP: x0 => x0.clientHeight,
      IQ: x0 => x0.latitude,
      IR: x0 => x0.databaseURL,
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      JC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      JD: x0 => x0.target,
      JE: (x0,x1) => x0.get(x1),
      JF: x0 => x0.pointerType,
      JG: x0 => x0.value,
      JH: x0 => x0.selectionEnd,
      JI: (a, i) => a.splice(i, 1),
      JJ: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      JK: (x0,x1) => { x0.height = x1 },
      JL: (x0,x1) => new Blob(x0,x1),
      JM: (x0,x1,x2,x3,x4) => ({padding: x0,pitch: x1,center: x2,zoom: x3,bearing: x4}),
      JN: x0 => x0.length,
      JO: (x0,x1,x2) => new File(x0,x1,x2),
      JP: x0 => x0.clientWidth,
      JQ: x0 => x0.coords,
      JR: x0 => x0.authDomain,
      K: o => o,
      KB: x0 => new Uint8Array(x0),
      KC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      KD: x0 => x0.clientY,
      KE: (o, p) => p in o,
      KF: x0 => x0.pointerId,
      KG: x0 => x0.done,
      KH: x0 => x0.value,
      KI: a => a.pop(),
      KJ: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      KK: (x0,x1) => { x0.width = x1 },
      KL: x0 => x0.persisted(),
      KM: (x0,x1) => x0.jumpTo(x1),
      KN: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      KO: (x0,x1) => { x0.type = x1 },
      KP: x0 => x0.tile,
      KQ: (x0,x1) => x0.clearWatch(x1),
      KR: x0 => x0.projectId,
      L: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      LB: x0 => new Uint8ClampedArray(x0),
      LC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      LD: x0 => x0.clientX,
      LE: (x0,x1) => { x0.textContent = x1 },
      LF: x0 => x0.getCoalescedEvents(),
      LG: (o, m, a) => o[m].apply(o, a),
      LH: x0 => x0.selectionDirection,
      LI: (map, o, v) => map.set(o, v),
      LJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      LK: x0 => x0.style,
      LL: (x0,x1,x2) => x0.setItem(x1,x2),
      LM: (x0,x1) => ({lng: x0,lat: x1}),
      LN: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      LO: x0 => x0.baseURI,
      LP: (x0,x1) => { x0.width = x1 },
      LQ: (x0,x1) => x0.query(x1),
      LR: x0 => x0.apiKey,
      M: x0 => x0.index,
      MB: x0 => new Int16Array(x0),
      MC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      MD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      ME: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      MF: (x0,x1) => x0.getModifierState(x1),
      MG: x0 => x0.iterator,
      MH: x0 => x0.selectionStart,
      MI: (map, o) => map.get(o),
      MJ: (x0,x1) => ({keyPath: x0,autoIncrement: x1}),
      MK: (x0,x1) => { x0.src = x1 },
      ML: (x0,x1) => x0.removeItem(x1),
      MM: (x0,x1,x2,x3) => ({top: x0,bottom: x1,right: x2,left: x3}),
      MN: x0 => x0.history,
      MO: x0 => x0.document,
      MP: (x0,x1) => { x0.height = x1 },
      MQ: x0 => x0.state,
      MR: x0 => x0.options,
      N: o => String(o),
      NB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      NC: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      ND: x0 => x0.getBoundingClientRect(),
      NE: x0 => x0.matches,
      NF: s => s.trimLeft(),
      NG: () => globalThis.Symbol,
      NH: x0 => x0.selectionEnd,
      NI: () => new WeakMap(),
      NJ: (x0,x1,x2) => x0.createObjectStore(x1,x2),
      NK: () => globalThis.document,
      NL: (x0,x1) => x0.getItem(x1),
      NM: x0 => x0.getCenter(),
      NN: x0 => x0.href,
      NO: x0 => x0.remove(),
      NP: (x0,x1) => { x0.margin = x1 },
      NQ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      NR: x0 => x0.name,
      O: o => o === undefined,
      OB: x0 => new Uint16Array(x0),
      OC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      OD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      OE: (x0,x1) => x0.matchMedia(x1),
      OF: s => s.toUpperCase(),
      OG: (x0,x1) => new Intl.Segmenter(x0,x1),
      OH: x0 => x0.keyCode,
      OI: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      OJ: (x0,x1) => x0.item(x1),
      OK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      OL: x0 => x0.localStorage,
      OM: x0 => x0.getZoom(),
      ON: x0 => x0.location,
      OO: (x0,x1) => x0.setMinZoom(x1),
      OP: (x0,x1) => { x0.padding = x1 },
      OQ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      OR: () => globalThis.firebase_core.getApps(),
      P: (x0,x1) => x0.exec(x1),
      PB: x0 => new Int32Array(x0),
      PC: (x0,x1) => x0.querySelector(x1),
      PD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      PE: x0 => x0.matches,
      PF: x0 => x0.pop(),
      PG: x0 => x0.Segmenter,
      PH: (x0,x1) => x0.scrollIntoView(x1),
      PI: (o, p) => p in o,
      PJ: x0 => x0.length,
      PK: x0 => x0.preventDefault(),
      PL: x0 => x0.decode(),
      PM: x0 => x0.getPitch(),
      PN: () => new Array(),
      PO: (x0,x1) => x0.setMaxZoom(x1),
      PP: (x0,x1) => x0.querySelector(x1),
      PQ: (x0,x1,x2,x3) => x0.getCurrentPosition(x1,x2,x3),
      PR: x0 => x0.name,
      Q: (x0,x1) => { x0.lastIndex = x1 },
      QB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      QC: (x0,x1) => x0.item(x1),
      QD: Date.now,
      QE: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      QF: x0 => x0.flags,
      QG: x0 => x0.buffer,
      QH: x0 => x0.multiViewEnabled,
      QI: x0 => x0.groups,
      QJ: x0 => x0.objectStoreNames,
      QK: x0 => x0.firstElementChild,
      QL: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      QM: x0 => x0.getBearing(),
      QN: (x0,x1) => new WebSocket(x0,x1),
      QO: (x0,x1) => x0.setMinPitch(x1),
      QP: (x0,x1) => x0.append(x1),
      QQ: x0 => x0.permissions,
      QR: (x0,x1,x2,x3,x4,x5,x6,x7) => ({apiKey: x0,authDomain: x1,databaseURL: x2,projectId: x3,storageBucket: x4,messagingSenderId: x5,measurementId: x6,appId: x7}),
      R: o => o,
      RB: x0 => new Uint32Array(x0),
      RC: x0 => x0.length,
      RD: (handle) => clearTimeout(handle),
      RE: f => f.dartFunction,
      RF: (a, s) => a.join(s),
      RG: x0 => x0.wasmMemory,
      RH: (x0,x1) => x0.replaceWith(x1),
      RI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      RJ: x0 => x0.target,
      RK: x0 => x0.src,
      RL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      RM: x0 => x0.lat,
      RN: x0 => x0.reason,
      RO: (x0,x1) => x0.setMaxPitch(x1),
      RP: (x0,x1) => { x0.id = x1 },
      RQ: x0 => x0.geolocation,
      RR: (x0,x1) => globalThis.firebase_core.initializeApp(x0,x1),
      S: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      SB: x0 => new Float32Array(x0),
      SC: (x0,x1) => x0.querySelectorAll(x1),
      SD: (a, l) => a.length = l,
      SE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      SF: (x0,x1) => x0.error(x1),
      SG: () => globalThis.window._flutter_skwasmInstance,
      SH: (x0,x1) => { x0.type = x1 },
      SI: (x0,x1,x2) => x0.addEventListener(x1,x2),
      SJ: (x0,x1) => x0.get(x1),
      SK: (x0,x1) => x0.revokeObjectURL(x1),
      SL: (x0,x1,x2) => x0.addEventListener(x1,x2),
      SM: x0 => x0.lng,
      SN: x0 => x0.code,
      SO: (x0,x1) => x0.setMaxBounds(x1),
      SP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      SQ: x0 => x0.origin,
      SR: () => globalThis.firebase_core.SDK_VERSION,
      T: o => o instanceof RegExp,
      TB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      TC: (x0,x1) => x0.getAttribute(x1),
      TD: (x0,x1) => x0.closest(x1),
      TE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      TF: () => globalThis.console,
      TG: () => new TextDecoder(),
      TH: (x0,x1) => { x0.className = x1 },
      TI: (x0,x1) => x0.getRegistration(x1),
      TJ: x0 => x0.getTime(),
      TK: (x0,x1) => { x0.src = x1 },
      TL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      TM: (x0,x1) => x0.project(x1),
      TN: (x0,x1,x2) => x0.close(x1,x2),
      TO: (x0,x1) => x0.setData(x1),
      TP: (x0,x1,x2,x3) => x0.toBlob(x1,x2,x3),
      TQ: (x0,x1) => { x0.src = x1 },
      TR: (x0,x1,x2) => globalThis.firebase_core.registerVersion(x0,x1,x2),
      U: (string, times) => string.repeat(times),
      UB: x0 => new Float64Array(x0),
      UC: x0 => x0.remove(),
      UD: x0 => x0.bottom,
      UE: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      UF: s => s.trimRight(),
      UG: (d, digits) => d.toFixed(digits),
      UH: (x0,x1) => { x0.tabIndex = x1 },
      UI: x0 => x0.update(),
      UJ: x0 => globalThis.Object.keys(x0),
      UK: (x0,x1,x2,x3,x4) => globalThis.createImageBitmap(x0,x1,x2,x3,x4),
      UL: x0 => x0.send(),
      UM: x0 => x0.y,
      UN: (x0,x1) => x0.close(x1),
      UO: x0 => x0.enable(),
      UP: x0 => x0.size,
      UQ: (x0,x1) => x0.getRandomValues(x1),
      UR: (x0,x1) => x0.debug(x1),
      V: o => o,
      VB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      VC: (x0,x1) => x0.appendChild(x1),
      VD: x0 => x0.top,
      VE: (o, i) => o[i],
      VF: x0 => x0.blur(),
      VG: x0 => x0.maxHeight,
      VH: (x0,x1) => { x0.name = x1 },
      VI: x0 => x0.data,
      VJ: x0 => x0.length,
      VK: x0 => x0.naturalHeight,
      VL: x0 => x0.status,
      VM: x0 => x0.x,
      VN: x0 => x0.close(),
      VO: x0 => x0.enable(),
      VP: (x0,x1,x2,x3) => x0.drawImage(x1,x2,x3),
      VQ: (x0,x1,x2,x3) => x0.encrypt(x1,x2,x3),
      VR: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      W: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      WB: x0 => new ArrayBuffer(x0),
      WC: (x0,x1) => x0.append(x1),
      WD: x0 => x0.right,
      WE: o => o.length,
      WF: x0 => x0.button,
      WG: x0 => x0.maxWidth,
      WH: (x0,x1) => { x0.placeholder = x1 },
      WI: x0 => x0.serviceWorker,
      WJ: (x0,x1,x2) => x0.put(x1,x2),
      WK: x0 => x0.naturalWidth,
      WL: x0 => x0.response,
      WM: x0 => x0.getStyle(),
      WN: (x0,x1) => x0.send(x1),
      WO: x0 => x0.enable(),
      WP: (x0,x1,x2,x3,x4,x5) => x0.drawImage(x1,x2,x3,x4,x5),
      WQ: x0 => x0.sessionStorage,
      WR: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      X: x0 => x0.dotAll,
      XB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      XC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      XD: x0 => x0.left,
      XE: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      XF: x0 => x0.innerHeight,
      XG: x0 => x0.minHeight,
      XH: (x0,x1) => { x0.autocomplete = x1 },
      XI: x0 => x0.navigator,
      XJ: x0 => x0.storage,
      XK: x0 => x0.decode(),
      XL: (x0,x1,x2) => x0.setRequestHeader(x1,x2),
      XM: x0 => x0.sources,
      XN: x0 => x0.readyState,
      XO: x0 => x0.enable(),
      XP: x0 => x0.height,
      XQ: x0 => x0.subtle,
      XR: (x0,x1) => ({createScript: x0,createScriptURL: x1}),
      Y: x0 => x0.unicode,
      YB: (x0,x1,x2) => new DataView(x0,x1,x2),
      YC: x0 => x0.style,
      YD: x0 => x0.clientY,
      YE: x0 => x0.language,
      YF: x0 => x0.innerWidth,
      YG: x0 => x0.minWidth,
      YH: (x0,x1) => { x0.name = x1 },
      YI: () => globalThis.window,
      YJ: x0 => x0.persist(),
      YK: (x0,x1) => { x0.decoding = x1 },
      YL: (x0,x1) => { x0.responseType = x1 },
      YM: (x0,x1) => x0.unproject(x1),
      YN: (x0,x1) => { x0.binaryType = x1 },
      YO: x0 => x0.enable(),
      YP: x0 => x0.width,
      YQ: (x0,x1,x2,x3,x4,x5,x6,x7) => x0.unwrapKey(x1,x2,x3,x4,x5,x6,x7),
      YR: (x0,x1,x2) => x0.createPolicy(x1,x2),
      Z: x0 => x0.ignoreCase,
      ZB: (o, p) => o[p],
      ZC: x0 => x0.debugShowSemanticsNodes,
      ZD: x0 => x0.clientX,
      ZE: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      ZF: x0 => x0.height,
      ZG: x0 => x0.debugSkipFontRetryDelay,
      ZH: (x0,x1) => { x0.placeholder = x1 },
      ZI: x0 => new WeakRef(x0),
      ZJ: (x0,x1) => x0.getRandomValues(x1),
      ZK: (x0,x1) => { x0.crossOrigin = x1 },
      ZL: () => new XMLHttpRequest(),
      ZM: (x0,x1) => new maplibregl.Point(x0,x1),
      ZN: x0 => new BroadcastChannel(x0),
      ZO: x0 => x0.enable(),
      ZP: (x0,x1) => x0.getContext(x1),
      ZQ: (x0,x1,x2,x3,x4,x5) => x0.importKey(x1,x2,x3,x4,x5),
      ZR: (x0,x1) => x0.createScriptURL(x1),
      a: x0 => x0.multiline,
      aB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      aC: (x0,x1) => x0.warn(x1),
      aD: x0 => x0.changedTouches,
      aE: () => globalThis.window.FinalizationRegistry,
      aF: x0 => x0.width,
      aG: x0 => x0.status,
      aH: (x0,x1) => { x0.action = x1 },
      aI: x0 => x0.deref(),
      aJ: () => globalThis.crypto,
      aK: (x0,x1) => x0.createObjectURL(x1),
      aL: x0 => x0.clearMarks(),
      aM: x0 => x0.getBounds(),
      aN: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      aO: x0 => x0.enableRotation(),
      aP: (x0,x1) => { x0.height = x1 },
      aQ: (x0,x1,x2,x3) => x0.generateKey(x1,x2,x3),
      aR: (x0,x1,x2) => x0.createScript(x1,x2),
      b: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      bB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      bC: x0 => x0.console,
      bD: x0 => x0.offsetY,
      bE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      bF: x0 => x0.clientHeight,
      bG: (x0,x1,x2) => x0.set(x1,x2),
      bH: (x0,x1) => { x0.method = x1 },
      bI: () => globalThis.WeakRef,
      bJ: l => new DataView(new ArrayBuffer(l)),
      bK: x0 => x0.URL,
      bL: x0 => x0.clearMeasures(),
      bM: x0 => x0.getWest(),
      bN: x0 => x0.close(),
      bO: x0 => x0.disableRotation(),
      bP: (x0,x1) => { x0.width = x1 },
      bQ: (x0,x1,x2,x3,x4) => x0.wrapKey(x1,x2,x3,x4),
      bR: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      c: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      cB: o => o.byteOffset,
      cC: () => globalThis.window,
      cD: x0 => x0.offsetX,
      cE: x0 => new window.FinalizationRegistry(x0),
      cF: x0 => x0.clientWidth,
      cG: x0 => x0.arrayBuffer(),
      cH: (x0,x1) => { x0.noValidate = x1 },
      cI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      cJ: x0 => new DecompressionStream(x0),
      cK: x0 => new Blob(x0),
      cL: (x0,x1) => x0.parse(x1),
      cM: x0 => x0.getEast(),
      cN: (x0,x1) => x0.postMessage(x1),
      cO: x0 => x0.disable(),
      cP: x0 => x0.height,
      cQ: (x0,x1,x2) => x0.exportKey(x1,x2),
      cR: (o, p) => delete o[p],
      d: (x0,x1) => x0.didCreateEngineInitializer(x1),
      dB: o => o.buffer,
      dC: (o, c) => o instanceof c,
      dD: x0 => x0.type,
      dE: (x0,x1) => x0.unregister(x1),
      dF: (x0,x1) => { x0.content = x1 },
      dG: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      dH: (x0,x1) => x0.removeAttribute(x1),
      dI: (a, s, e) => a.slice(s, e),
      dJ: x0 => new Blob(x0),
      dK: x0 => x0.close(),
      dL: (x0,x1,x2) => x0.mark(x1,x2),
      dM: x0 => x0.getSouth(),
      dN: (x0,x1) => { x0.onmessage = x1 },
      dO: x0 => x0.enable(),
      dP: x0 => x0.width,
      dQ: x0 => x0.crypto,
      dR: (x0,x1) => { x0.text = x1 },
      e: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      eB: Function.prototype.call.bind(DataView.prototype.getUint8),
      eC: (x0,x1) => x0[x1],
      eD: x0 => x0.maxTouchPoints,
      eE: (x0,x1) => x0.contains(x1),
      eF: (x0,x1) => { x0.name = x1 },
      eG: (x0,x1) => x0.fetch(x1),
      eH: x0 => x0.isConnected,
      eI: x0 => x0.indexedDB,
      eJ: x0 => x0.stream(),
      eK: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      eL: (x0,x1,x2,x3) => x0.measure(x1,x2,x3),
      eM: x0 => x0.getNorth(),
      eN: x0 => x0.canvasKitMaximumSurfaces,
      eO: x0 => x0.disable(),
      eP: (x0,x1) => { x0.src = x1 },
      eQ: x0 => x0.isSecureContext,
      eR: (x0,x1) => { x0.text = x1 },
      f: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      fB: (b, o) => new DataView(b, o),
      fC: x0 => x0.length,
      fD: x0 => x0.platform,
      fE: (s) => +s,
      fF: x0 => x0.head,
      fG: x0 => x0.fontFallbackBaseUrl,
      fH: x0 => x0.click(),
      fI: (x0,x1,x2) => x0.open(x1,x2),
      fJ: (x0,x1) => ({readable: x0,writable: x1}),
      fK: (x0,x1) => x0.decode(x1),
      fL: (o) => {
        const typeofValue = typeof o;
        return (typeofValue === 'object') ||
            typeofValue === 'function';
      },
      fM: (x0,x1) => x0.getLayer(x1),
      fN: x0 => x0.nextSibling,
      fO: x0 => x0.enable(),
      fP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fQ: (x0,x1,x2,x3) => x0.decrypt(x1,x2,x3),
      fR: x0 => x0.trustedTypes,
      g: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      gB: (b, o, l) => new DataView(b, o, l),
      gC: (string, token) => string.split(token),
      gD: x0 => x0.body,
      gE: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      gF: (x0,x1) => x0.removeChild(x1),
      gG: (handle) => clearInterval(handle),
      gH: (x0,x1) => x0.getElementsByClassName(x1),
      gI: x0 => x0.close(),
      gJ: (x0,x1) => x0.pipeThrough(x1),
      gK: x0 => x0.displayHeight,
      gL: () => globalThis.JSON,
      gM: (x0,x1,x2,x3,x4,x5,x6) => ({id: x0,type: x1,layout: x2,paint: x3,minzoom: x4,maxzoom: x5,source: x6}),
      gN: (x0,x1) => x0.debug(x1),
      gO: x0 => x0.disable(),
      gP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gQ: x0 => x0.message,
      gR: () => globalThis.console,
      h: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      hB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      hC: o => o instanceof Array,
      hD: () => globalThis.document,
      hE: s => s.trim(),
      hF: x0 => x0.firstChild,
      hG: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      hH: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      hI: x0 => x0.message,
      hJ: x0 => new Response(x0),
      hK: x0 => x0.displayWidth,
      hL: x0 => x0.clearMarks,
      hM: (x0,x1,x2) => x0.addLayer(x1,x2),
      hN: x0 => x0.hostElement,
      hO: x0 => x0.keyboard,
      hP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      hQ: x0 => x0.code,
      hR: x0 => x0.trustedTypes,
      i: x0 => new Promise(x0),
      iB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      iC: (a, i) => a[i],
      iD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      iE: x0 => x0.classList,
      iF: x0 => x0.viewConstraints,
      iG: () => Date.now(),
      iH: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      iI: x0 => x0.name,
      iJ: x0 => x0.arrayBuffer(),
      iK: x0 => x0.duration,
      iL: x0 => x0.clearMeasures,
      iM: (x0,x1) => x0.getSource(x1),
      iN: x0 => x0.location,
      iO: x0 => x0.touchPitch,
      iP: (x0,x1) => { x0.oncancel = x1 },
      iQ: () => globalThis.Notification.requestPermission(),
      iR: (x0,x1) => { x0.crossOrigin = x1 },
      j: (x0,x1,x2) => x0.call(x1,x2),
      jB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      jC: a => a.length,
      jD: x0 => x0.hasFocus(),
      jE: x0 => x0.preventDefault(),
      jF: x0 => x0.hostElement,
      jG: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      jH: (x0,x1) => x0.dispatchEvent(x1),
      jI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      jJ: x0 => x0.writable,
      jK: x0 => x0.image,
      jL: x0 => x0.mark,
      jM: x0 => globalThis.JSON.parse(x0),
      jN: (x0,x1) => x0.getModifierState(x1),
      jO: x0 => x0.dragRotate,
      jP: (x0,x1) => { x0.onchange = x1 },
      jQ: (x0,x1) => x0.register(x1),
      jR: (x0,x1) => { x0.type = x1 },
      k: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      kB: (t, s) => t.set(s),
      kC: (x0,x1) => x0.test(x1),
      kD: x0 => x0.relatedTarget,
      kE: x0 => x0.parent,
      kF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      kG: x0 => x0.history,
      kH: (x0,x1) => x0.createEvent(x1),
      kI: (x0,x1) => { x0.onversionchange = x1 },
      kJ: x0 => x0.readable,
      kK: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      kL: x0 => x0.measure,
      kM: (x0,x1) => ({type: x0,data: x1}),
      kN: x0 => x0.metaKey,
      kO: x0 => x0.boxZoom,
      kP: x0 => x0.type,
      kQ: (x0,x1) => ({vapidKey: x0,serviceWorkerRegistration: x1}),
      kR: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      l: x0 => new Array(x0),
      lB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      lC: x0 => x0.userAgent,
      lD: x0 => x0.shiftKey,
      lE: x0 => x0.timeStamp,
      lF: x0 => ({runApp: x0}),
      lG: x0 => x0.search,
      lH: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      lI: (x0,x1,x2) => x0.transaction(x1,x2),
      lJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      lK: x0 => new window.ImageDecoder(x0),
      lL: () => globalThis.performance,
      lM: (x0,x1,x2) => x0.addSource(x1,x2),
      lN: x0 => x0.altKey,
      lO: x0 => x0.scrollZoom,
      lP: x0 => x0.lastModified,
      lQ: (x0,x1) => globalThis.firebase_messaging.getToken(x0,x1),
      lR: x0 => x0.message,
      m: o => [o],
      mB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      mC: x0 => x0.navigator,
      mD: (decoder, codeUnits) => decoder.decode(codeUnits),
      mE: (x0,x1) => x0.hasAttribute(x1),
      mF: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      mG: x0 => x0.location,
      mH: x0 => x0.readText(),
      mI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      mJ: x0 => x0.abort(),
      mK: x0 => x0.name,
      mL: (x0,x1) => x0.getAllKeys(x1),
      mM: (x0,x1,x2) => ({type: x0,url: x1,coordinates: x2}),
      mN: x0 => x0.ctrlKey,
      mO: x0 => x0.doubleClickZoom,
      mP: x0 => x0.name,
      mQ: x0 => x0.link,
      mR: x0 => x0.length,
      n: (o0, o1) => [o0, o1],
      nB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      nC: Function.prototype.call.bind(String.prototype.toLowerCase),
      nD: () => new TextDecoder("utf-8", {fatal: true}),
      nE: x0 => x0.buttons,
      nF: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      nG: x0 => x0.pathname,
      nH: x0 => x0.clipboard,
      nI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      nJ: () => new AbortController(),
      nK: x0 => x0.repetitionCount,
      nL: (x0,x1,x2,x3) => x0.putImageData(x1,x2,x3),
      nM: (x0,x1) => x0.removeSource(x1),
      nN: x0 => x0.isComposing,
      nO: x0 => x0.touchZoomRotate,
      nP: (x0,x1) => x0.item(x1),
      nQ: x0 => x0.analyticsLabel,
      nR: x0 => x0.getReader(),
      o: (o0, o1, o2) => [o0, o1, o2],
      oB: Function.prototype.call.bind(DataView.prototype.getUint32),
      oC: Object.is,
      oD: () => new TextDecoder("utf-8", {fatal: false}),
      oE: x0 => x0.ctrlKey,
      oF: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      oG: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      oH: (x0,x1) => x0.writeText(x1),
      oI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      oJ: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      oK: x0 => x0.frameCount,
      oL: x0 => x0.arrayBuffer(),
      oM: (x0,x1) => x0.removeLayer(x1),
      oN: x0 => x0.code,
      oO: x0 => x0.dragPan,
      oP: x0 => x0.length,
      oQ: x0 => x0.image,
      oR: x0 => x0.value,
      p: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      pB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      pC: x0 => x0.vendor,
      pD: (a, i, v) => a[i] = v,
      pE: x0 => x0.y,
      pF: () => typeof dartUseDateNowForTicks !== "undefined",
      pG: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      pH: x0 => x0.unlock(),
      pI: (x0,x1) => { x0.oncomplete = x1 },
      pJ: (x0,x1) => globalThis.fetch(x0,x1),
      pK: x0 => x0.selectedTrack,
      pL: (x0,x1) => x0.transferFromImageBitmap(x1),
      pM: (x0,x1) => x0.appendChild(x1),
      pN: x0 => x0.repeat,
      pO: () => new pmtiles.Protocol(),
      pP: x0 => x0.files,
      pQ: x0 => x0.body,
      pR: x0 => x0.done,
      q: (x0,x1,x2) => { x0[x1] = x2 },
      qB: Function.prototype.call.bind(DataView.prototype.getInt32),
      qC: (x0,x1) => x0.createTextNode(x1),
      qD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      qE: x0 => x0.x,
      qF: () => Date.now(),
      qG: o => Object.keys(o),
      qH: (x0,x1) => x0.lock(x1),
      qI: (x0,x1) => { x0.onabort = x1 },
      qJ: (x0,x1) => x0.get(x1),
      qK: x0 => x0.completed,
      qL: x0 => x0.height,
      qM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      qN: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      qO: (x0,x1) => globalThis.maplibregl.addProtocol(x0,x1),
      qP: (x0,x1) => x0.replaceChildren(x1),
      qQ: x0 => x0.title,
      qR: x0 => x0.read(),
      r: (o, p) => o[p],
      rB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      rC: (x0,x1) => { x0.id = x1 },
      rD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      rE: x0 => x0.scrollTop,
      rF: () => 1000 * performance.now(),
      rG: x0 => x0.state,
      rH: x0 => x0.orientation,
      rI: (x0,x1) => { x0.onerror = x1 },
      rJ: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      rK: x0 => x0.ready,
      rL: x0 => x0.width,
      rM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      rN: x0 => x0.userAgent,
      rO: (x0,x1,x2,x3,x4,x5,x6) => ({style: x0,container: x1,zoom: x2,center: x3,bearing: x4,pitch: x5,attributionControl: x6}),
      rP: (x0,x1,x2) => x0.setAttribute(x1,x2),
      rQ: x0 => x0.fcmOptions,
      rR: x0 => x0.body,
      s: () => globalThis,
      sB: o => o instanceof Uint16Array,
      sC: (x0,x1) => { x0.nonce = x1 },
      sD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      sE: x0 => x0.offsetTop,
      sF: (x0,x1) => x0.requestAnimationFrame(x1),
      sG: x0 => x0.hash,
      sH: (x0,x1) => x0.querySelector(x1),
      sI: x0 => x0.message,
      sJ: (x0,x1) => x0.forEach(x1),
      sK: x0 => x0.tracks,
      sL: x0 => x0.rasterEndMilliseconds,
      sM: (x0,x1) => { x0.onerror = x1 },
      sN: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      sO: x0 => new maplibregl.Map(x0),
      sP: (x0,x1) => { x0.accept = x1 },
      sQ: x0 => x0.notification,
      sR: x0 => x0.assetBase,
      t: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      tB: Function.prototype.call.bind(DataView.prototype.getUint16),
      tC: x0 => x0.nonce,
      tD: x0 => x0.visibilityState,
      tE: x0 => x0.scrollLeft,
      tF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      tG: x0 => x0.state,
      tH: (x0,x1) => { x0.title = x1 },
      tI: x0 => x0.name,
      tJ: x0 => x0.statusText,
      tK: () => globalThis.window.ImageDecoder,
      tL: x0 => x0.rasterStartMilliseconds,
      tM: (x0,x1) => { x0.onload = x1 },
      tN: (x0,x1) => x0.key(x1),
      tO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      tP: (x0,x1) => { x0.multiple = x1 },
      tQ: x0 => x0.messageId,
      tR: x0 => x0.loader,
      u: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      uB: o => o instanceof Int16Array,
      uC: () => globalThis.window.flutterConfiguration,
      uD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      uE: x0 => x0.offsetLeft,
      uF: x0 => x0.now(),
      uG: (x0,x1) => x0.go(x1),
      uH: (x0,x1) => x0.vibrate(x1),
      uI: x0 => x0.error,
      uJ: x0 => x0.url,
      uK: () => new FileReader(),
      uL: x0 => x0.imageBitmaps,
      uM: (x0,x1) => { x0.async = x1 },
      uN: x0 => x0.length,
      uO: (x0,x1,x2) => x0.on(x1,x2),
      uP: (x0,x1) => { x0.type = x1 },
      uQ: x0 => x0.from,
      uR: () => globalThis._flutter,
      v: (x0,x1) => ({addView: x0,removeView: x1}),
      vB: Function.prototype.call.bind(DataView.prototype.getInt16),
      vC: (x0,x1) => x0.attachShadow(x1),
      vD: x0 => x0.disconnect(),
      vE: x0 => x0.offsetParent,
      vF: x0 => x0.performance,
      vG: x0 => x0.parentElement,
      vH: x0 => x0.content,
      vI: (x0,x1) => x0.objectStore(x1),
      vJ: x0 => x0.status,
      vK: (x0,x1) => x0.readAsArrayBuffer(x1),
      vL: (x0,x1) => { x0.height = x1 },
      vM: (x0,x1) => { x0.src = x1 },
      vN: (x0,x1) => x0.canShare(x1),
      vO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      vP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      vQ: x0 => x0.collapseKey,
      w: (l, r) => l === r,
      wB: o => o instanceof Uint8ClampedArray,
      wC: (x0,x1) => x0.createElement(x1),
      wD: x0 => new Intl.Locale(x0),
      wE: (o, p, r) => o.replace(p, () => r),
      wF: x0 => new Uint8Array(x0),
      wG: (x0,x1) => x0.querySelectorAll(x1),
      wH: x0 => x0.document,
      wI: x0 => x0.autoIncrement,
      wJ: x0 => x0.getReader(),
      wK: x0 => x0.result,
      wL: (x0,x1) => { x0.width = x1 },
      wM: (x0,x1) => x0.createElement(x1),
      wN: (x0,x1) => x0.share(x1),
      wO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      wP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      wQ: x0 => x0.data,
      x: x0 => x0.random(),
      xB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      xC: x0 => x0.scale,
      xD: x0 => x0.region,
      xE: (o, p, r) => o.replaceAll(p, () => r),
      xF: (x0,x1,x2) => x0.slice(x1,x2),
      xG: (x0,x1) => x0.removeProperty(x1),
      xH: (x0,x1,x2) => x0.insertBefore(x1,x2),
      xI: (o, t) => typeof o === t,
      xJ: x0 => x0.read(),
      xK: () => new XMLHttpRequest(),
      xL: x0 => x0.convertToBlob(),
      xM: x0 => x0.head,
      xN: x0 => x0.click(),
      xO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      xP: (x0,x1,x2) => ({enableHighAccuracy: x0,timeout: x1,maximumAge: x2}),
      xQ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      y: () => globalThis.Math,
      yB: Function.prototype.call.bind(DataView.prototype.setInt32),
      yC: x0 => x0.visualViewport,
      yD: x0 => x0.script,
      yE: x0 => x0.deltaMode,
      yF: (x0,x1) => x0.decode(x1),
      yG: (x0,x1) => x0.add(x1),
      yH: x0 => x0.id,
      yI: x0 => x0.keyPath,
      yJ: x0 => x0.value,
      yK: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      yL: (x0,x1,x2) => new ImageData(x0,x1,x2),
      yM: () => globalThis.document,
      yN: x0 => x0.remove(),
      yO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      yP: (x0,x1,x2,x3) => x0.watchPosition(x1,x2,x3),
      yQ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      z: (x0,x1) => x0.prepend(x1),
      zB: Function.prototype.call.bind(DataView.prototype.setUint32),
      zC: x0 => x0.devicePixelRatio,
      zD: x0 => x0.language,
      zE: x0 => x0.deltaY,
      zF: (x0,x1) => x0.adoptText(x1),
      zG: x0 => x0.data,
      zH: x0 => x0.offsetHeight,
      zI: x0 => x0.name,
      zJ: x0 => x0.done,
      zK: x0 => x0.send(),
      zL: (x0,x1) => x0.getContext(x1),
      zM: (x0,x1) => { x0.href = x1 },
      zN: (o, a) => o + a,
      zO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      zP: x0 => x0.message,
      zQ: (x0,x1) => ({next: x0,error: x1}),

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
