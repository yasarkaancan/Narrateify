import Foundation
import AVFoundation
@main struct Test {
 static func tick(_ duration: Double) { RunLoop.main.run(until:Date().addingTimeInterval(duration)) }
 static func waitFor(_ predicate: () -> Bool) {
  let deadline=Date().addingTimeInterval(6)
  while !predicate() && Date()<deadline { tick(0.05) }
 }
 static func main() throws {
  let path=URL(fileURLWithPath:CommandLine.arguments[1])
  let a=AudioController(); a.rate=1; var finished=0
  a.onFinished={finished += 1}
  a.beginStreaming(minimumBuffer:2)
  a.enqueueStreaming(url:path);tick(0.3)
  precondition(a.currentTime < 0.05,"Started before buffer")
  a.pause();a.enqueueStreaming(url:path);tick(0.3)
  precondition(!a.isPlaying && a.currentTime < 0.05,"Enqueue overrode pause")
  a.play();tick(0.5)
  precondition(a.currentTime > 0.1,"Resume failed")
  a.pause();let paused=a.currentTime
  a.enqueueStreaming(url:path);tick(0.4)
  precondition(!a.isPlaying && abs(a.currentTime-paused)<0.25,"Paused playback advanced")
  a.seek(to:1.2);tick(0.2)
  precondition(!a.isPlaying,"Seek overrode pause")
  a.sealStreaming();a.play();waitFor { finished == 1 }
  precondition(finished==1 && !a.streaming,"Stream did not finish exactly once")
  a.beginStreaming(minimumBuffer:18);a.enqueueStreaming(url:path);a.sealStreaming();waitFor { finished == 2 }
  precondition(finished==2,"Short final stream never started or completed")
  a.beginStreaming(minimumBuffer:18);a.stop();a.enqueueStreaming(url:path);tick(0.2)
  precondition(!a.hasAudio && !a.isPlaying && !a.streaming,"Stopped stream restarted")
  print("PASS: buffer threshold, pause during buffering, pause on chunk arrival, resume, paused seek, sealed completion, short stream, stop rejects late chunk.")
 }
}
