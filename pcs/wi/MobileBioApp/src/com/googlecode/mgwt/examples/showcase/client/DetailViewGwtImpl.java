package com.googlecode.mgwt.examples.showcase.client;

import com.google.gwt.user.client.ui.HTML;
import com.google.gwt.user.client.ui.HasHorizontalAlignment;
import com.google.gwt.user.client.ui.HasText;
import com.google.gwt.user.client.ui.HorizontalPanel;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.PopupPanel;
import com.google.gwt.user.client.ui.Widget;
import com.googlecode.mgwt.dom.client.event.tap.HasTapHandlers;
import com.googlecode.mgwt.dom.client.event.tap.TapEvent;
import com.googlecode.mgwt.dom.client.event.tap.TapHandler;
import com.googlecode.mgwt.examples.showcase.client.header.HeaderRightWidgetPanelViewGwtImpl;
import com.googlecode.mgwt.ui.client.MGWT;
import com.googlecode.mgwt.ui.client.MGWTStyle;
import com.googlecode.mgwt.ui.client.widget.HeaderButton;
import com.googlecode.mgwt.ui.client.widget.HeaderPanel;
import com.googlecode.mgwt.ui.client.widget.LayoutPanel;
import com.googlecode.mgwt.ui.client.widget.ScrollPanel;
import com.googlecode.mgwt.ui.client.widget.buttonbar.ArrowDownButton;
import com.googlecode.mgwt.ui.client.widget.buttonbar.ArrowUpButton;

public abstract class DetailViewGwtImpl implements DetailView {

	protected LayoutPanel main;
	protected ScrollPanel scrollPanel;
	protected HeaderPanel headerPanel;
	protected HeaderButton headerBackButton;
	protected HeaderButton headerMainButton;
	protected HTML title;
	protected HorizontalPanel hPanel;
	protected ArrowDownButton arrowDownButton;
	protected ArrowUpButton arrowUpButton;
	
	public DetailViewGwtImpl() {
		main = new LayoutPanel();

		scrollPanel = new ScrollPanel();

		headerPanel = new HeaderPanel();
		title = new HTML();
		headerPanel.setCenterWidget(title);
		headerBackButton = new HeaderButton();
		headerBackButton.setBackButton(true);
		headerBackButton.setVisible(!MGWT.getOsDetection().isAndroid());

		headerMainButton = new HeaderButton();
		headerMainButton.setRoundButton(true);
			
		arrowUpButton = new ArrowUpButton();
		arrowDownButton = new ArrowDownButton();	
		hPanel = new HorizontalPanel();
		hPanel.add(arrowDownButton);
		hPanel.setCellHorizontalAlignment(arrowDownButton, HasHorizontalAlignment.ALIGN_RIGHT);
		//headerPanel.setRightWidget(hPanel);
	
		
		arrowUpButton.addTapHandler(new TapHandler(){

			@Override
			public void onTap(TapEvent event) {
				
				
			}
			
		});
		
		
		System.out.println("Device is phone: " + MGWT.getOsDetection().isPhone());
		
		if (!MGWT.getOsDetection().isPhone()) {
			headerPanel.setLeftWidget(headerMainButton);
			headerMainButton.addStyleName(MGWTStyle.getTheme().getMGWTClientBundle().getUtilCss().portraitonly());
		} else {
			headerPanel.setLeftWidget(headerBackButton);
		}

		main.add(headerPanel);
		main.add(scrollPanel);
	}
	
	@Override
	public Widget asWidget() {
		return main;
	}

	@Override
	public HasText getHeader() {
		return title;
	}

	@Override
	public HasText getBackbuttonText() {
		return headerBackButton;
	}

	@Override
	public HasTapHandlers getBackbutton() {
		return headerBackButton;
	}

	@Override
	public HasText getMainButtonText() {
		return headerMainButton;
	}

	@Override
	public HasTapHandlers getMainButton() {
		return headerMainButton;
	}

}
