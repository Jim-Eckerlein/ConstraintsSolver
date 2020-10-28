//
//  CollisionDetection.swift
//  ConstraintsSolver
//
//  Created by Jim Eckerlein on 24.10.20.
//

import Foundation

infix operator ~=: ComparisonPrecedence

func ~=(_ x1: simd_float3, _ x2: simd_float3) -> Bool {
    let epsilon: Float = 0.0001
    let difference = abs(x1 - x2)
    return difference.x < epsilon && difference.y < epsilon && difference.z < epsilon
}

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

enum TriangleEdge {
    case left
    case right
    case bottom
}

/// Possible outcomes of a triangle-triangle intersection test.
/// Degenerate cases are not considered.
enum TriangleIntersection {
    case contained
    case extendingBeyondLeftEdge(TriangleEdge)
    case extendingBeyondBottomEdge(TriangleEdge)
    case extendingBeyondRightEdge(TriangleEdge)
    case extentingAcrossLeftBottomEdges
    case extentingAcrossLeftRightEdges
    case extentingAcrossBottomRightEdges
}

/// Compute the intersection of the given triangles if intersect in a non-degenerate line segment.
func triangleIntersection(_ a: Triangle, _ b: Triangle) -> (TriangleIntersection, LineSegment)? {
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
    var segments: [(Triangle, LineSegment, Triangle)]
}

extension Geometry {
    
    func adjacentTriangle(of triangle: Triangle, edge: TriangleEdge) -> Triangle {
        let a: simd_float3
        let b: simd_float3
        
        switch edge {
        case .left:
            a = triangle.points.0
            b = triangle.points.1
        case .bottom:
            a = triangle.points.1
            b = triangle.points.2
        case .right:
            a = triangle.points.2
            b = triangle.points.0
        }
        
        for t in triangles() {
            if (a ~= t.points.1 && b ~= t.points.0) ||
                (a ~= t.points.2 && b ~= t.points.1) ||
                (a ~= t.points.0 && b ~= t.points.2) {
                return t
            }
        }
        
        fatalError("Mesh not closed")
    }
    
    func expandSeam(otherGeometry: Geometry, t1 initialT1: Triangle, t2 initialT2: Triangle) -> IntersectionSeam {
        var seam = IntersectionSeam(segments: [])
        
        var ownTriangle = initialT1
        var otherTriangle = initialT2
        
        while let (intersection, segment) = triangleIntersection(ownTriangle, otherTriangle) {
            seam.segments.append((ownTriangle, segment, otherTriangle))
            
            switch intersection {
            
            case .extendingBeyondRightEdge(let penetratingEdge):
                otherTriangle = otherGeometry.adjacentTriangle(of: otherTriangle, edge: penetratingEdge)
            
            case .extendingBeyondLeftEdge(let otherPenetratingEdge):
                ownTriangle = adjacentTriangle(of: ownTriangle, edge: .left)
                
            case .extendingBeyondBottomEdge:
                otherTriangle = otherGeometry.adjacentTriangle(of: otherTriangle, edge: 0)
                
//            case .containing:
//                otherTriangle =
            
            default:
                fatalError()
            }
        }
        
        
    }
    
    func intersect(with otherGeometry: Geometry) {
        let otherTriangles = otherGeometry.triangles()

        for ownTriangle in triangles() {
            for otherTriangle in otherGeometry.triangles() {
                if let (intersection, segment) = triangleIntersection(ownTriangle, otherTriangle) {
                    switch intersection {
                    case .extendingBeyondLeftEdge(let edge) {
                        
                    }
                    default:
                        fatalError()
                    }
                }
                
//                switch triangleIntersection(t1, t2) {
//                case .none:
//                    continue
//                //                case let .containing(lineSegment):
//                //                    <#code#>
//                case let .extendingBeyondLeftEdge(lineSegment):
//                    // Follow seam to left edge.
//                    let nextTriangle = adjacentTriangle(of: t1, edge: 0)
//                    expandSeam(otherGeometry: otherGeometry, t1: nextTriangle, t2: t2)
//
////                    let nextIntersection = triangleIntersection(nextTriangle, t2)
//
//                //                case let .extendingBeyondEdge1(lineSegment):
//                //                    <#code#>
//                //                case let .extendingBeyondEdge2(lineSegment):
//                //                    <#code#>
//                default:
//                    fatalError()
//                }
            }
        }
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
