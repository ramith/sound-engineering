// ruleid: coreaudio-listener-not-on-main
AudioObjectAddPropertyListenerBlock(id, &addr, DispatchQueue.main) { _, _ in }
// ok: coreaudio-listener-not-on-main
// AudioObjectAddPropertyListenerBlock(id, &addr, DispatchQueue.main) { _, _ in }
