use crate::Datapoint;
use serde::{Deserialize, Serialize};
use statrs::statistics::{Distribution as StatsrsDistribution, Max, Median, Min, OrderStatistics};
use std::fmt::{Display, Formatter};

#[derive(Debug, Serialize, Deserialize, Copy, Clone)]
pub struct Statistics {
    pub rx_packets: Distribution,
    pub rx_bytes: Distribution,
}

#[derive(Debug, Serialize, Deserialize, Copy, Clone)]
pub struct Distribution {
    pub total: u64,
    pub min: f64,
    pub max: f64,
    pub mean: f64,
    pub variance: f64,
    pub std_dev: f64,
    pub median: f64,
    pub q25: f64,
    pub q75: f64,
    pub min_without_outliers: f64,
    pub max_without_outliers: f64,
}

impl Display for Statistics {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "=== RX Packets ===\n{}\n\n=== RX Bytes ===\n{}",
            self.rx_packets, self.rx_bytes
        )
    }
}

impl Display for Distribution {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Total: {}\nMin: {}\nMax: {}\nMean: {}\nVariance: {}\nStd Dev: {}\nMedian: {}",
            self.total, self.min, self.max, self.mean, self.variance, self.std_dev, self.median
        )
    }
}

pub fn calculate_statistics(datapoints: &[Datapoint]) -> Statistics {
    let rx_packets: Vec<_> = datapoints
        .iter()
        .map(|datapoint| datapoint.rx_packets)
        .collect();
    let rx_bytes: Vec<_> = datapoints
        .iter()
        .map(|datapoint| datapoint.rx_bytes)
        .collect();

    let rx_packets_distribution = calculate_distribution(&rx_packets);
    let rx_bytes_distribution = calculate_distribution(&rx_bytes);

    Statistics {
        rx_packets: rx_packets_distribution,
        rx_bytes: rx_bytes_distribution,
    }
}

fn calculate_distribution(points: &[u64]) -> Distribution {
    let derivative = derivative(points);
    let mut data = statrs::statistics::Data::new(derivative);

    let min = data.min();
    let max = data.max();
    let mean = data.mean().expect("cannot calculate mean");
    let variance = data.variance().expect("cannot calculate variance");
    let std_dev = data.std_dev().expect("cannot calculate std dev");
    let median = data.median();
    let total = points.last().copied().expect("cannot calculate total");
    let q25 = data.percentile(25);
    let q75 = data.percentile(75);
    let iqr = data.interquartile_range();

    let considered_min_without_outliers = q25 - 1.5 * iqr;
    let considered_max_without_outliers = q75 + 1.5 * iqr;

    let min_without_outliers = *data
        .iter()
        .filter(|&x| *x >= considered_min_without_outliers)
        .min_by(|a, b| a.total_cmp(b))
        .expect("cannot calculate min without outliers");
    let max_without_outliers = *data
        .iter()
        .filter(|&x| *x <= considered_max_without_outliers)
        .max_by(|a, b| a.total_cmp(b))
        .expect("cannot calculate max without outliers");

    Distribution {
        total,
        min,
        max,
        mean,
        variance,
        std_dev,
        median,
        min_without_outliers,
        max_without_outliers,
        q25,
        q75,
    }
}

pub fn derivative(points: &[u64]) -> Vec<f64> {
    points
        .windows(2)
        .map(|window| {
            let (x1, x2) = (window[0] as f64, window[1] as f64);
            x2 - x1
        })
        .collect()
}
