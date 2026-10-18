// SPDX-License-Identifier: MIT
// Development test adapter. The Linux package does not depend on this program.
use std::{net::SocketAddr, sync::Arc};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init();
    let local: std::net::IpAddr = "127.0.0.1".parse()?;
    let matches: Vec<_> = rusb::devices()?
        .iter()
        .filter(|device| {
            device
                .device_descriptor()
                .map(|d| d.vendor_id() == 0x04f9 && d.product_id() == 0x60e2)
                .unwrap_or(false)
        })
        .collect();
    if matches.len() != 1 {
        return Err("Exactly one physical DS-720D is required".into());
    }
    let device = &matches[0];
    let config = device.active_config_descriptor()?;
    let interfaces: Vec<_> = config.interfaces().collect();
    if config.number() != 1 || interfaces.len() != 1 {
        return Err("Unexpected scanner USB configuration".into());
    }
    let descriptor = interfaces[0]
        .descriptors()
        .next()
        .ok_or("Missing interface descriptor")?;
    if descriptor.setting_number() != 0
        || (
            descriptor.class_code(),
            descriptor.sub_class_code(),
            descriptor.protocol_code(),
        ) != (8, 6, 0x50)
    {
        return Err("Unexpected scanner USB interface".into());
    }
    let handle = device.open()?;
    handle.claim_interface(descriptor.interface_number())?;
    let devices = usbip::UsbIpServer::with_rusb_device_handles(vec![handle]);
    if devices.len() != 1 {
        return Err("Physical scanner export failed".into());
    }
    println!(
        "Exporting physical 04f9:60e2 as {} on localhost:3240 only",
        devices[0].bus_id
    );
    // This upstream constructor retains the physical libusb handlers above.
    let server = Arc::new(usbip::UsbIpServer::new_simulated(devices));
    let listener = TcpListener::bind("127.0.0.1:3240".parse::<SocketAddr>()?).await?;
    loop {
        let (mut socket, peer) = listener.accept().await?;
        if peer.ip() != local {
            continue;
        }
        socket.set_nodelay(true)?;
        let server = server.clone();
        tokio::spawn(async move {
            if let Err(error) = usbip::handler(&mut socket, server).await {
                eprintln!("USB/IP connection: {error:?}");
            }
        });
    }
}
