// The terminal's commands, on MockInstall's lot without a window.

import Foundation
import LotScene
import SimAntics
import Testing

private let simburbiaFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// The mock lot, with the mock ball added out of the world.
private func lotWithBall() throws -> (LotSession, Int16) {
    let session = try LotSession(ClientOptions(installs: [], simburbiaFolder: simburbiaFolder))
    let ball = try #require(try session.vm.createObject(guid: 0x4D4F_4308)?.objects.first)
    return (session, ball.objectID)
}

@Test func theTerminalAnswersHelpAndUnknownCommands() throws {
    let (session, _) = try lotWithBall()
    var terminal = TerminalCommands()
    #expect(terminal.run("help", on: session.vm) == TerminalCommands.help)
    #expect(terminal.run("   ", on: session.vm).isEmpty)
    #expect(terminal.run("dance", on: session.vm) == ["unknown command 'dance'; try help"])
    #expect(terminal.run("show", on: session.vm) == ["no Sim; try join"])
    #expect(terminal.run("sims", on: session.vm) == ["no Sims; try join"])
}

/// Join the mock Sim, see what the ball offers it, queue a dance, and cancel it.
@Test func theTerminalQueuesAnInteractionForAJoinedSim() throws {
    let (session, ball) = try lotWithBall()
    var terminal = TerminalCommands()
    let joined = terminal.run("join Tester", on: session.vm)
    let sim = try #require(terminal.simID)
    #expect(joined == ["Tester joined as \(sim)"])
    #expect(terminal.run("sims", on: session.vm) == ["\(sim)  Tester  (acting for)"])
    #expect(terminal.run("objects ball", on: session.vm) == ["\(ball)  mockball"])
    #expect(terminal.run("menu \(ball)", on: session.vm) == ["0  Dance With", "1  Pick Up"])
    #expect(terminal.run("queue \(ball) 0", on: session.vm) == ["queued as action 0"])
    #expect(terminal.run("show", on: session.vm) == ["0  Dance With  on \(ball)  waiting"])
    #expect(terminal.run("cancel 0", on: session.vm) == ["cancelling action 0"])
    #expect(terminal.run("show", on: session.vm) == ["Tester's queue is empty"])
    #expect(terminal.run("cancel 0", on: session.vm) == ["Tester has no action 0"])
}

@Test func theTerminalExplainsWhatItCantDo() throws {
    let (session, ball) = try lotWithBall()
    var terminal = TerminalCommands()
    _ = terminal.run("join", on: session.vm)
    #expect(terminal.run("queue", on: session.vm) == ["usage: queue <object> <n>"])
    #expect(terminal.run("queue \(ball) x", on: session.vm) == ["usage: queue <object> <n>"])
    #expect(terminal.run("queue 999 0", on: session.vm) == ["no object 999"])
    #expect(terminal.run("queue \(ball) 7", on: session.vm) == ["no interaction 7 there"])
    #expect(terminal.run("menu", on: session.vm) == ["usage: menu <object>"])
    #expect(terminal.run("sim \(ball)", on: session.vm) == ["\(ball) isn't a Sim"])
    #expect(terminal.run("sim 99999", on: session.vm) == ["usage: sim <id>"])
    #expect(terminal.run("menu 1", on: session.vm).count == 1, "an object without a table offers nothing")
}
