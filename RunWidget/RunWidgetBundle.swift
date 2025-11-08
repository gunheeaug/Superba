//
//  RunWidgetBundle.swift
//  RunWidget
//
//  Created by Gunhee Han on 11/8/25.
//

import WidgetKit
import SwiftUI

@main
struct RunWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunWidget()
        RunWidgetControl()
        RunWidgetLiveActivity()
    }
}
