//
//  SkillsCatalog.swift
//  TradeBase
//
//  Created by Assistant on 07/10/2025.
//

import Foundation

struct SkillsCatalog {
    static func skills(for trade: TradeType) -> [String] {
        switch trade {
        case .electrician:
            return [
                "Wiring Installation",
                "Panel Upgrades", 
                "Lighting Installation",
                "Outlet Installation",
                "Circuit Breaker Work",
                "Electrical Troubleshooting",
                "Smart Home Systems",
                "EV Charging Stations"
            ]
            
        case .plumber:
            return [
                "Pipe Installation",
                "Leak Repairs",
                "Drain Cleaning",
                "Water Heater Installation",
                "Bathroom Plumbing",
                "Kitchen Plumbing",
                "Emergency Repairs",
                "Gas Line Work"
            ]
            
        case .carpenter:
            return [
                "Framing",
                "Custom Cabinets",
                "Trim Work",
                "Door Installation",
                "Window Installation",
                "Deck Building",
                "Furniture Making",
                "Finish Carpentry"
            ]
            
        case .roofer:
            return [
                "Shingle Installation",
                "Tile Roofing",
                "Metal Roofing",
                "Flat Roofing",
                "Gutter Installation",
                "Roof Repairs",
                "Leak Detection",
                "Skylight Installation"
            ]
            
        case .painter:
            return [
                "Interior Painting",
                "Exterior Painting",
                "Wallpaper Hanging",
                "Staining",
                "Spraying",
                "Surface Preparation",
                "Color Consultation",
                "Decorative Finishes"
            ]
            
        case .hvac:
            return [
                "AC Installation",
                "Heating Installation",
                "Duct Work",
                "System Maintenance",
                "Energy Audits",
                "Heat Pump Installation",
                "Thermostat Installation",
                "Air Quality Systems"
            ]
            
        case .tiler:
            return [
                "Ceramic Tiling",
                "Natural Stone",
                "Mosaic Work",
                "Bathroom Tiling",
                "Kitchen Backsplashes",
                "Floor Tiling",
                "Waterproofing",
                "Grout Work"
            ]
            
        case .landscaper:
            return [
                "Garden Design",
                "Lawn Installation",
                "Tree Planting",
                "Irrigation Systems",
                "Hardscaping",
                "Deck Installation",
                "Fence Installation",
                "Maintenance Services"
            ]
            
        case .generalBuilder:
            return [
                "Home Extensions",
                "Kitchen Renovations", 
                "Bathroom Renovations",
                "Basement Finishing",
                "Loft Conversions",
                "Project Management",
                "Building Maintenance",
                "Property Development",
                "Planning Applications",
                "Building Regulations",
                "Structural Work",
                "Insulation",
                "Drywall Installation",
                "Flooring Installation"
            ]

        case .windowsAndDoors:
            return [
                "uPVC Window Installation",
                "Timber Window Installation",
                "Aluminium Window Installation",
                "Double/Triple Glazing",
                "Window Repairs",
                "Glass Replacement",
                "Draught Proofing",
                "External Door Installation",
                "Internal Door Hanging",
                "Composite Doors",
                "Bi‑fold Door Installation",
                "Sliding Patio Doors",
                "French Doors",
                "Door Repairs and Re‑alignment",
                "Lock and Hardware Fitting",
                "Cat Flap Fitting"
            ]
        }
    }
}
