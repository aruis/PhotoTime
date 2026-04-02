import Darwin
import Foundation

struct MemorySnapshot {
    let residentSizeBytes: UInt64

    var residentSizeMB: Double {
        Double(residentSizeBytes) / 1_048_576.0
    }
}

enum MemoryProbe {
    nonisolated static func current() -> MemorySnapshot? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }

        guard status == KERN_SUCCESS else { return nil }
        return MemorySnapshot(residentSizeBytes: UInt64(info.resident_size))
    }
}
