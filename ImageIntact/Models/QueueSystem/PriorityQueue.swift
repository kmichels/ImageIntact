import Foundation

/// Thread-safe priority queue for FileTask objects
actor PriorityQueue {
    private var heap: [FileTask] = []
    private let comparator: (FileTask, FileTask) -> Bool
    
    init(ascending: Bool = false) {
        // Higher score = higher priority (comes out first)
        self.comparator = ascending ? { $0.score < $1.score } : { $0.score > $1.score }
    }
    
    var count: Int {
        heap.count
    }
    
    var isEmpty: Bool {
        heap.isEmpty
    }
    
    func enqueue(_ task: FileTask) {
        heap.append(task)
        heapifyUp(from: heap.count - 1)
    }
    
    func enqueueMultiple(_ tasks: [FileTask]) {
        for task in tasks {
            heap.append(task)
            heapifyUp(from: heap.count - 1)
        }
    }
    
    func dequeue() -> FileTask? {
        guard !heap.isEmpty else { return nil }
        
        if heap.count == 1 {
            return heap.removeFirst()
        }
        
        let first = heap[0]
        heap[0] = heap.removeLast()
        heapifyDown(from: 0)
        
        return first
    }
    
    func peek() -> FileTask? {
        heap.first
    }
    
    func clear() {
        heap.removeAll()
    }
    
    /// Get all tasks without removing them (for UI display)
    func allTasks() -> [FileTask] {
        heap.sorted { comparator($0, $1) }
    }
    
    /// Remove a specific task (e.g., if user cancels one file)
    func remove(_ taskId: UUID) -> FileTask? {
        guard let index = heap.firstIndex(where: { $0.id == taskId }) else {
            return nil
        }
        
        let task = heap[index]
        
        if index == heap.count - 1 {
            heap.removeLast()
        } else {
            heap[index] = heap.removeLast()
            // Determine whether to heapify up or down
            if index > 0 && comparator(heap[index], heap[(index - 1) / 2]) {
                heapifyUp(from: index)
            } else {
                heapifyDown(from: index)
            }
        }
        
        return task
    }
    
    // MARK: - Private Heap Operations
    
    private func heapifyUp(from index: Int) {
        var childIndex = index
        let child = heap[childIndex]
        var parentIndex = (childIndex - 1) / 2
        
        while childIndex > 0 && comparator(child, heap[parentIndex]) {
            heap[childIndex] = heap[parentIndex]
            childIndex = parentIndex
            parentIndex = (childIndex - 1) / 2
        }
        
        heap[childIndex] = child
    }
    
    private func heapifyDown(from index: Int) {
        var parentIndex = index
        let parent = heap[parentIndex]
        let count = heap.count
        
        while true {
            let leftChildIndex = 2 * parentIndex + 1
            let rightChildIndex = leftChildIndex + 1
            
            var candidateIndex = parentIndex
            
            if leftChildIndex < count && comparator(heap[leftChildIndex], heap[candidateIndex]) {
                candidateIndex = leftChildIndex
            }
            
            if rightChildIndex < count && comparator(heap[rightChildIndex], heap[candidateIndex]) {
                candidateIndex = rightChildIndex
            }
            
            if candidateIndex == parentIndex {
                break
            }
            
            heap[parentIndex] = heap[candidateIndex]
            parentIndex = candidateIndex
        }
        
        heap[parentIndex] = parent
    }
}