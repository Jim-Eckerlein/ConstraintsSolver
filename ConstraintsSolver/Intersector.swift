//
//  Intersector.swift
//  ConstraintsSolver
//
//  Created by Jim Eckerlein on 28.10.20.
//

import Foundation

func intersectGround(_ rigidBody: RigidBody) -> [PositionalConstraint] {
    rigidBody.vertices().filter { vertex in vertex.z < 0 }.map { position in
        let targetPosition = double3(position.x, position.y, 0)
        let difference = targetPosition - position
        
        let deltaPosition = position - rigidBody.intoPreviousAttidue(position)
        let deltaTangentialPosition = deltaPosition - project(deltaPosition, difference)
        
        return PositionalConstraint(
            body: rigidBody,
            positions: (position, targetPosition - deltaTangentialPosition),
            distance: 0,
            compliance: 0.0000001
        )
    }
}

struct MinkowskiDifference {
    let convexVolumes: (ConvexVolume, ConvexVolume)
    
    init(_ a: ConvexVolume, _ b: ConvexVolume) {
        convexVolumes = (a, b)
    }
    
    /// Returns the point within the Minkowski difference which is furthest away from the origin in the given direction.
    subscript (in direction: double3) -> double3 {
        convexVolumes.0.furthestPoint(in: direction) - convexVolumes.1.furthestPoint(in: -direction)
    }
}

protocol ConvexVolume {
    func furthestPoint(in direction: double3) -> double3
}

/// 0-, 1-, or 2-simplices which arise during the iterations of the GJK algorithm.
fileprivate enum IntermediateSimplex {
    case point(double3)
    case line(double3, double3)
    case triangle(double3, double3, double3)
}

typealias Tetrahedron = (double3, double3, double3, double3)

/// The simplex after an iteration is either still an intermediate one, or the final tetrahedron which contains the origin.
fileprivate enum NextSimplex {
    case intermediate(IntermediateSimplex)
    case containingTetrahedron(Tetrahedron)
}

func gjk(a: ConvexVolume, b: ConvexVolume) -> Bool {
    let support = MinkowskiDifference(a, b)
    
    let initialPoint = support[in: double3.random(in: 0...1)]
    var simplex = IntermediateSimplex.point(initialPoint)
    var searchDirection = -initialPoint
    
    while true {
        let nextPoint = support[in: searchDirection]
        
        if dot(nextPoint, searchDirection) <= 0 {
            // No collision possible anymore.
            return false
        }
        
        switch nextSimplex(simplex: simplex, point: nextPoint, direction: &searchDirection) {
        case let .intermediate(nextSimplex):
            simplex = nextSimplex
        case .containingTetrahedron:
            return true
        }
    }
}

fileprivate func nextSimplex(simplex: IntermediateSimplex, point a: double3, direction: inout double3) -> NextSimplex {
    switch simplex {
    case let .point(b):
        return .intermediate(processLine(a, b, direction: &direction))
    case let .line(b, c):
        return .intermediate(processTriangle(a, b, c, direction: &direction))
    case let .triangle(b, c, d):
        if let simplex = processTetrahedron(a, b, c, d, direction: &direction) {
            return .intermediate(simplex)
        }
        else {
            return .containingTetrahedron(Tetrahedron(a, b, c, d))
        }
    }
}

extension double3 {
    func cross(_ x: double3) -> double3 {
        simd.cross(self, x)
    }
    
    func dot(_ x: double3) -> Double {
        simd.dot(self, x)
    }
}

fileprivate func sameDirection(_ a: double3, _ b: double3) -> Bool {
    dot(a, b) > 0
}

fileprivate func processLine(_ a: double3, _ b: double3, direction: inout double3) -> IntermediateSimplex {
    let ao = -a
    let ab = b - a
    if sameDirection(cross(a, b), ao) {
        direction = ab.cross(ao).cross(ab)
        return .line(a, b)
    }
    else {
        direction = ao
        return .point(a)
    }
}

fileprivate func processTriangle(_ a: double3, _ b: double3, _ c: double3, direction: inout double3) -> IntermediateSimplex {
    let ao = -a
    let ab = b - a
    let ac = c - a
    let abc = ab.cross(ac)
    
    if sameDirection(abc.cross(ac), ao) {
        if sameDirection(ac, ao) {
            direction = ac.cross(ao).cross(ac)
            return .line(a, c)
        }
        else {
            return processLine(a, b, direction: &direction)
        }
    }
    else {
        if sameDirection(ab.cross(abc), ao) {
            return processLine(a, b, direction: &direction)
        }
        else if sameDirection(abc, ao) {
            direction = abc
            return .triangle(a, b, c)
        }
        else {
            direction = -abc
            return .triangle(a, c, b)
        }
    }
}

fileprivate func processTetrahedron(_ a: double3, _ b: double3, _ c: double3, _ d: double3, direction: inout double3) -> IntermediateSimplex? {
    let ab = b - a
    let ac = c - a
    let ad = d - a
    let ao = -a
    
    let abc = ab.cross(ac)
    let acd = ac.cross(ad)
    let adb = ad.cross(ab)
    
    if sameDirection(abc, ao) {
        return processTriangle(a, b, c, direction: &direction)
    }
    else if sameDirection(acd, ao) {
        return processTriangle(a, c, d, direction: &direction)
    }
    else if sameDirection(adb, ao) {
        return processTriangle(a, d, b, direction: &direction)
    }
    else {
        return .none
    }
}
