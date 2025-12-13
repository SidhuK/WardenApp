import Foundation

actor StreamingTaskController {
    private var currentTaskID: UUID?
    private var currentTask: Task<Void, Never>?
    
    func replace(taskID: UUID, task: Task<Void, Never>) {
        currentTask?.cancel()
        currentTaskID = taskID
        currentTask = task
    }
    
    func cancelAndClear() {
        currentTask?.cancel()
        currentTaskID = nil
        currentTask = nil
    }
    
    func clearIfCurrent(taskID: UUID) {
        guard currentTaskID == taskID else { return }
        currentTaskID = nil
        currentTask = nil
    }
}

