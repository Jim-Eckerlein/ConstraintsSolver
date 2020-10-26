//
//  CollisionDetection.swift
//  ConstraintsSolver
//
//  Created by Jim Eckerlein on 24.10.20.
//

import Foundation

struct Triangle {
    let points: (simd_float3, simd_float3, simd_float3)
    let normal: simd_float3
    let offset: Float
    
    init(_ p0: simd_float3, _ p1: simd_float3, _ p2: simd_float3) {
        points = (p0, p1, p2)
        normal = cross(p1 - p0, p2 - p0)
        offset = dot(-normal, p0)
    }
    
    func planarDistance(to x: simd_float3) -> Float {
        dot(normal, x) + offset
    }
}

func rayTriangleIntersection(origin: simd_float3, ray: simd_float3, triangle: Triangle) -> simd_float3? {
    let EPSILON: Float = 0.0000001
    let vertex0 = triangle.points.0
    let vertex1 = triangle.points.1
    let vertex2 = triangle.points.2
    
    let edge1 = vertex1 - vertex0
    let edge2 = vertex2 - vertex0
    
    let h = cross(ray, edge2)
    let a = dot(edge1, h)
    
    if (a > -EPSILON && a < EPSILON) {
        // This ray is parallel to this triangle.
        return .none
    }
    
    let f = 1.0 / a
    let s = origin - vertex0
    let u = f * dot(s, h)
    
    if (u < 0.0 || u > 1.0) {
        return .none
    }
    
    let q = cross(s, edge1)
    let v = f * dot(ray, q)
    
    if (v < 0.0 || u + v > 1.0) {
        return .none
    }
    
    // At this stage we can compute t to find out where the intersection point is on the line.
    let t = f * dot(edge2, q)
    if (t > EPSILON) {
        return .some(origin + ray * t)
    }
    else {
        // This means that there is a line intersection but not a ray intersection.
        return .none
    }
}

struct LineSegment {
    let from: simd_float3
    let to: simd_float3
    
    var segment: simd_float3 {
        get {
            return to - from
        }
    }
}

/// Compute the intersection of the given triangles if intersect in a non-degenerate line segment.
func triangleIntersection(_ a: Triangle, _ b: Triangle) -> LineSegment? {
    fatalError()
}

struct IntersectionDomain {
    let inside: Bool
    let subMesh: [Triangle]
    let seams: [Triangle]
    
    func depth(along direction: simd_float3, from origin: simd_float3) -> Float {
        var depth = -Float.infinity
        for triangle in subMesh {
            let t0 = dot(direction, triangle.points.0 - origin)
            let t1 = dot(direction, triangle.points.1 - origin)
            let t2 = dot(direction, triangle.points.2 - origin)
            depth = max(depth, max(t0, max(t1, t2)))
        }
        return depth
    }
}

struct IntersectionSeam {
    let segments: [(Triangle, LineSegment)]
}

extension Geometry {
    
    func intersect(with other: Geometry) {
//        let otherTriangles = other.triangles()
        
//        for t1 in triangles() {
//            for t2 in other.triangles() {
//                if let intersectingLineSegment = triangleIntersection(t1, t2) {
//                    
//                }
//            }
//        }
    }
    
    /// Tests if the given point lies inside the geometry's volume.
//    func isInside(point: simd_float3) {
//        let ray = simd_float3.random(in: 0...1)
//        var
//
//        // Count triangles which intersect with the ray.
//        for triangle in triangles() {
//            if let intersection = rayTriangleIntersection(origin: point, ray: ray, triangle: triangle) {
//                if dot(triangle.normal, ray) > 0 {
//                    // The triangle normal has a similar direction as the ray, so it exits the volume at the intersection point.
//
//                }
//            }
//        }
//    }
    
}
