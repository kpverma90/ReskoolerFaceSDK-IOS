import { NativeModulesProxy, EventEmitter, Subscription } from 'expo-modules-core';
import ReskoolerFaceModule from './src/ReskoolerFaceModule';

export function startFaceSDK(mode) {
  return ReskoolerFaceModule.startFaceSDK(mode);
}

export function stopFaceSDK() {
  return ReskoolerFaceModule.stopFaceSDK();
}

export function setGallery(embeddings) {
  return ReskoolerFaceModule.setGallery(embeddings);
}

const emitter = new EventEmitter(ReskoolerFaceModule ?? NativeModulesProxy.ReskoolerFace);

export function addFaceResultListener(listener) {
  return emitter.addListener('onFaceResult', listener);
}
